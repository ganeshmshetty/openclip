// MacTextRetriever.swift
// OpenClip
//
// Retrieves selected text from active macOS applications using AXUIElement accessibility APIs and pasteboard fallbacks.
import AppKit
import ApplicationServices
import Foundation
import Core
import os

// MARK: - MacTextRetriever

/// Retrieves selected text from macOS applications using a two-strategy chain:
/// 1. Accessibility (AX) direct attribute read – fastest, no side effects.
/// 2. Safari JS selection read (Safari AX can be delayed).
/// Apps explicitly opted-in via `grabPasteboard` policy use a Cmd+C keystroke fallback.
internal final class MacTextRetriever: TextRetrieving, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.openclip", category: "MacTextRetriever")

    internal init() {}

    // MARK: - TextRetrieving

    internal func retrieveText(for app: AppIdentity, policy: AppPolicyContext) async -> String? {
        await retrieveTextResult(for: app, policy: policy)?.text
    }

    internal func retrieveTextResult(for app: AppIdentity, policy: AppPolicyContext) async -> TextResult? {
        // `grabPasteboard` is an explicit per-app policy that opts into Cmd+C behaviour.
        // Never send Cmd+C by default — OpenClip uses AX selection only, with no clipboard side-effects.
        if policy.grabPasteboard {
            if let text = await strategyKeyboardShortcut() {
                return TextResult(text: text, bounds: nil)
            }
            return nil
        }

        // Strategy 1: Accessibility direct read — instant, zero side-effects.
        if let result = await strategyAXDirect() {
            return result
        }

        // Strategy 1.5: Safari JS selection read (Safari AX can be delayed).
        if let safariText = await strategySafariJS(for: app),
           !safariText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextResult(text: safariText, bounds: nil)
        }

        // Strategy 2 (menu copy) and Strategy 3 (Cmd+C) removed:
        // They silently copy text to the clipboard, which is unexpected behaviour.
        // Only apps explicitly opted-in via grabPasteboard policy use Cmd+C.

        return nil
    }
    
    private func strategySafariJS(for app: AppIdentity) async -> String? {
        guard app.bundleIdentifier == "com.apple.Safari" else { return nil }
        let script = """
        tell application "Safari"
            if (count of documents) > 0 then
                do JavaScript "window.getSelection().toString()" in front document
            end if
        end tell
        """
        let text = await runAppleScript(script)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Strategy 1: AX Direct

    /// Read selected text directly using Accessibility APIs:
    /// 1. Focused UI element
    /// 2. Hit-test element under mouse cursor (`AXUIElementCopyElementAtPosition`)
    /// 3. Ancestor hierarchy walk (up to 4 levels)
    private func strategyAXDirect() async -> TextResult? {
        return await withCheckedContinuation { continuation in
            Task.detached { [logger] in
                let systemWide = AXUIElementCreateSystemWide()
                
                // 1. Try focused UI element
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                   let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
                    let focusedElement = focusedRef as! AXUIElement
                    if let result = self.extractTextAndBounds(from: focusedElement) {
                        logger.debug("AX strategy: success from focused element (\(result.text.count) chars)")
                        continuation.resume(returning: result)
                        return
                    }
                    
                    // Try ancestors of focused element (up to 4 levels)
                    if let ancestorResult = self.extractFromAncestors(element: focusedElement, maxDepth: 4) {
                        logger.debug("AX strategy: success from focused element ancestor (\(ancestorResult.text.count) chars)")
                        continuation.resume(returning: ancestorResult)
                        return
                    }
                }
                
                // 2. Try hit-test element under mouse cursor
                if let mouseLocation = CGEvent(source: nil)?.location {
                    var hitElement: AXUIElement?
                    if AXUIElementCopyElementAtPosition(systemWide, Float(mouseLocation.x), Float(mouseLocation.y), &hitElement) == .success,
                       let hitElement {
                        if let result = self.extractTextAndBounds(from: hitElement) {
                            logger.debug("AX strategy: success from cursor hit-test element (\(result.text.count) chars)")
                            continuation.resume(returning: result)
                            return
                        }
                        
                        // Try ancestors of hit-test element (up to 4 levels)
                        if let ancestorResult = self.extractFromAncestors(element: hitElement, maxDepth: 4) {
                            logger.debug("AX strategy: success from cursor hit-test ancestor (\(ancestorResult.text.count) chars)")
                            continuation.resume(returning: ancestorResult)
                            return
                        }
                    }
                }
                
                logger.debug("AX strategy: all direct AX resolution attempts exhausted")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Walk up element's parent hierarchy (maxDepth levels) looking for selected text.
    private func extractFromAncestors(element: AXUIElement, maxDepth: Int) -> TextResult? {
        var current = element
        for _ in 0..<maxDepth {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef, CFGetTypeID(parentRef) == AXUIElementGetTypeID() else {
                break
            }
            let parent = parentRef as! AXUIElement
            if CFEqual(current, parent) { break }
            if let result = extractTextAndBounds(from: parent) {
                return result
            }
            current = parent
        }
        return nil
    }

    /// Extract selected text and bounds from an AX element, trying kAXSelectedTextAttribute first,
    /// then falling back to kAXValueAttribute + kAXSelectedTextRangeAttribute substring extraction.
    private func extractTextAndBounds(from element: AXUIElement) -> TextResult? {
        var textRef: CFTypeRef?
        var selectedText: String? = nil
        
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
           let text = textRef as? String, !text.isEmpty {
            selectedText = text
        } else {
            // Fallback: Check kAXValueAttribute and kAXSelectedTextRangeAttribute
            var valueRef: CFTypeRef?
            var rangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let fullValue = valueRef as? String, !fullValue.isEmpty,
               AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
               let rangeVal = rangeRef {
                var cfRange = CFRange()
                if AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange),
                   cfRange.length > 0,
                   cfRange.location >= 0,
                   cfRange.location + cfRange.length <= fullValue.count {
                    let start = fullValue.index(fullValue.startIndex, offsetBy: cfRange.location)
                    let end = fullValue.index(start, offsetBy: cfRange.length)
                    selectedText = String(fullValue[start..<end])
                }
            }
        }
        
        guard let text = selectedText, !text.isEmpty else { return nil }
        
        // Bounds extraction
        var bounds: CGRect? = nil
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
               let boundsRef {
                var rect = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) {
                    bounds = rect
                }
            }
        }
        
        return TextResult(text: text, bounds: bounds)
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
                    let src = CGEventSource(stateID: .combinedSessionState)
                    src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
                    let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
                    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: true)
                    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: false)
                    keyDown?.flags = flags
                    keyUp?.flags = flags
                    if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                        keyDown?.postToPid(pid)
                        keyUp?.postToPid(pid)
                    } else {
                        keyDown?.post(tap: .cgSessionEventTap)
                        keyUp?.post(tap: .cgSessionEventTap)
                    }
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
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let script = NSAppleScript(source: source) else { return nil }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                return error == nil ? result.stringValue : nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
