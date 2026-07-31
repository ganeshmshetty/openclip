import AppKit
import ApplicationServices
import Foundation
import Core
import os

// MARK: - MacTextRetriever

/// Retrieves selected text from macOS applications using a three-strategy chain:
/// 1. Accessibility (AX) direct attribute read – fastest, no side effects.
/// 2. Menu-action Copy – presses the "Copy" item in the frontmost app's Edit menu,
///    then polls the pasteboard; saves and restores original pasteboard contents.
/// 3. Keyboard shortcut Cmd+C – fallback; mutes system beep, polls pasteboard;
///    saves and restores original pasteboard contents.
internal final class MacTextRetriever: TextRetrieving, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.openclip", category: "MacTextRetriever")

    internal init() {}

    // MARK: - TextRetrieving

    internal func retrieveText(for app: any AppIdentifying, policy: AppPolicyContext) async -> String? {
        await retrieveTextResult(for: app, policy: policy)?.text
    }

    internal func retrieveTextResult(for app: any AppIdentifying, policy: AppPolicyContext) async -> TextResult? {
        // `grabPasteboard` means the caller wants us to go straight to Cmd+C.
        if policy.grabPasteboard {
            if let text = await strategyKeyboardShortcut() {
                return TextResult(text: text, bounds: nil)
            }
            return nil
        }

        // Strategy 1: Accessibility direct read
        if let result = await strategyAXDirect() {
            return result
        }

        // Strategy 2: Menu-action Copy
        if let text = await strategyMenuActionCopy() {
            return TextResult(text: text, bounds: nil)
        }

        // Strategy 3: Keyboard shortcut Cmd+C
        if let text = await strategyKeyboardShortcut() {
            return TextResult(text: text, bounds: nil)
        }

        return nil
    }

    // MARK: - Strategy 1: AX Direct

    /// Read `kAXSelectedTextAttribute` and optional `kAXBoundsForRangeParameterizedAttribute` from the focused UI element.
    private func strategyAXDirect() async -> TextResult? {
        return await withCheckedContinuation { continuation in
            // Run on a detached task so we don't block the caller's executor.
            Task.detached { [logger] in
                let systemWide = AXUIElementCreateSystemWide()
                var focusedRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    systemWide,
                    kAXFocusedUIElementAttribute as CFString,
                    &focusedRef
                ) == .success, let focusedRef else {
                    logger.debug("AX strategy: could not obtain focused element")
                    continuation.resume(returning: nil)
                    return
                }
                guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
                    continuation.resume(returning: nil)
                    return
                }
                let element = focusedRef as! AXUIElement
                var textRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    element,
                    kAXSelectedTextAttribute as CFString,
                    &textRef
                ) == .success, let text = textRef as? String else {
                    logger.debug("AX strategy: kAXSelectedTextAttribute unavailable")
                    continuation.resume(returning: nil)
                    return
                }
                guard !text.isEmpty else {
                    logger.debug("AX strategy: selected text is empty, falling through")
                    continuation.resume(returning: nil)
                    return
                }

                // Query text bounds via kAXSelectedTextRangeAttribute & kAXBoundsForRangeParameterizedAttribute
                var bounds: CGRect? = nil
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    &rangeRef
                ) == .success, let rangeRef {
                    var boundsRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(
                        element,
                        kAXBoundsForRangeParameterizedAttribute as CFString,
                        rangeRef,
                        &boundsRef
                    ) == .success, let boundsRef {
                        var rect = CGRect.zero
                        if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) {
                            bounds = rect
                        }
                    }
                }

                logger.debug("AX strategy: success (\(text.count) chars, bounds: \(bounds?.debugDescription ?? "none"))")
                continuation.resume(returning: TextResult(text: text, bounds: bounds))
            }
        }
    }

    // MARK: - Strategy 2: Menu-Action Copy

    /// Locate the enabled "Copy" item in the frontmost application's AX menu bar,
    /// press it, then poll the pasteboard for a change.
    /// Saves and restores all pasteboard items around the operation.
    @MainActor
    private func strategyMenuActionCopy() async -> String? {
        guard let copyItem = findEnabledCopyMenuItem() else {
            logger.debug("Menu strategy: no enabled Copy menu item found")
            return nil
        }
        logger.debug("Menu strategy: found enabled Copy menu item, pressing it")
        return await fetchPasteboardText(timeout: 0.3) {
            AXUIElementPerformAction(copyItem, kAXPressAction as CFString)
        }
    }

    /// Walk the frontmost application's AX menu bar looking for an enabled "Copy" item.
    /// Mirrors `AXManager.findEnabledMenuItem(.copy)` from SelectedTextKit.
    @MainActor
    private func findEnabledCopyMenuItem() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get the menu bar
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        ) == .success, let menuBarRef else { return nil }
        let menuBar = menuBarRef as! AXUIElement

        // Iterate top-level menus (File, Edit, View, …)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            menuBar,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let childrenRef else { return nil }

        let topMenus = childrenRef as! [AXUIElement]
        for menu in topMenus {
            if let copyItem = searchForCopyItem(in: menu) {
                return copyItem
            }
        }
        return nil
    }

    /// Recursively search an AX menu element for an enabled item whose title is "Copy".
    private func searchForCopyItem(in element: AXUIElement) -> AXUIElement? {
        // Check if this element itself is the Copy item
        if isCopyItem(element), isEnabled(element) {
            return element
        }

        // Descend into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let childrenRef else { return nil }

        for child in (childrenRef as! [AXUIElement]) {
            if let found = searchForCopyItem(in: child) {
                return found
            }
        }
        return nil
    }

    private func isCopyItem(_ element: AXUIElement) -> Bool {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleRef
        ) == .success, let title = titleRef as? String else { return false }
        return title == "Copy"
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledRef
        ) == .success, let enabled = enabledRef as? Bool else { return false }
        return enabled
    }

    // MARK: - Strategy 3: Keyboard Shortcut (Cmd+C)

    /// Post a synthetic Cmd+C keystroke, then poll the pasteboard for a change.
    /// Mutes the system beep so an empty-selection Copy is silent.
    /// Saves and restores all pasteboard items around the operation.
    private func strategyKeyboardShortcut() async -> String? {
        logger.debug("Keyboard strategy: sending Cmd+C")
        return await fetchPasteboardText(timeout: 0.5) {
            Task {
                await self.withMutedAlertVolume {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: true)
                    keyDown?.flags = .maskCommand
                    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: false)
                    keyUp?.flags = .maskCommand
                    keyDown?.post(tap: .cghidEventTap)
                    keyUp?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: - Shared Pasteboard Polling

    /// Save the current pasteboard, perform `action`, poll every 5 ms up to `timeout`
    /// seconds for the change count to advance, read the new string, then restore the
    /// original contents after 50 ms.
    ///
    /// - Parameters:
    ///   - timeout: Maximum seconds to wait for the pasteboard change count to advance.
    ///   - action: Closure that triggers a copy operation (menu press or key event).
    /// - Returns: The new string on the pasteboard, or `nil` on timeout / non-string content.
    @MainActor
    private func fetchPasteboardText(
        timeout: TimeInterval,
        action: @escaping () -> Void
    ) async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        action()

        // Poll every 5 ms
        let pollInterval: TimeInterval = 0.005
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != initialChangeCount { break }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        guard pasteboard.changeCount != initialChangeCount else {
            logger.debug("Pasteboard strategy: timed out waiting for change")
            // Restore immediately since we never changed anything meaningful
            restorePasteboard(pasteboard, items: savedItems)
            return nil
        }

        let text = pasteboard.string(forType: .string)
        let changeCountAfterCopy = pasteboard.changeCount

        // Restore original contents after a short delay so the paste operation
        // (if any downstream code uses the pasteboard) can complete first.
        Task { @MainActor [logger] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
            if NSPasteboard.general.changeCount == changeCountAfterCopy {
                self.restorePasteboard(NSPasteboard.general, items: savedItems)
                logger.debug("Pasteboard strategy: original contents restored")
            }
        }

        return text?.isEmpty == false ? text : nil
    }

    // MARK: - Pasteboard Save / Restore Helpers

    private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            let types = item.types // snapshot before clearing
            for type in types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    // MARK: - Beep Suppression

    /// Run `operation` with the system alert volume muted, restoring it asynchronously afterwards.
    private func withMutedAlertVolume<T>(_ operation: () async -> T) async -> T {
        var originalVolume: Int? = nil
        
        // Single combined AppleScript call to get and mute in one roundtrip
        let muteScript = """
        tell application "System Events"
            set originalVolume to alert volume of (get volume settings)
            set volume alert volume 0
            return originalVolume
        end tell
        """
        
        if let result = await runAppleScript(muteScript), let vol = Int(result) {
            originalVolume = vol
            logger.debug("Beep suppression: muted alert volume (was \(vol))")
        }
        
        let result = await operation()
        
        // Restore volume asynchronously without blocking the return
        if let vol = originalVolume, vol > 0 {
            Task.detached { [logger] in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s delay
                let restoreScript = """
                tell application "System Events"
                    set volume alert volume \(vol)
                end tell
                """
                _ = await self.runAppleScript(restoreScript)
                logger.debug("Beep suppression: restored alert volume to \(vol)")
            }
        }
        
        return result
    }

    /// Run an AppleScript on a background thread with a timeout and return its string output.
    private func runAppleScript(_ source: String, timeout: TimeInterval = 0.2) async -> String? {
        return await withCheckedContinuation { continuation in
            let task = Task.detached { () -> String? in
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    return nil
                }
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    return nil
                }
                return result.stringValue
            }
            
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                task.cancel()
            }
            
            Task.detached {
                let val = await task.value
                continuation.resume(returning: val)
            }
        }
    }
}
