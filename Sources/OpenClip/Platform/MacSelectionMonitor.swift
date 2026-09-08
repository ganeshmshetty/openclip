// MacSelectionMonitor.swift
// OpenClip
//
// Monitors macOS mouse and keyboard events to detect text selection actions and trigger OpenClip
// popup presentation. Every trigger passes the `isSuppressed` gate first (wired to the popup's
// modal result card by AppDelegate), so while that card is open no selection is read at all.
import AppKit
import Core

@MainActor
internal final class MacSelectionMonitor: SelectionMonitoring {
    /// Selection context + the paste-availability probe result for the source app (`nil` when the
    /// app is excluded or the probe never ran).
    internal var onSelection: ((SelectionContext, Bool?) -> Void)?
    /// Starts the paste-availability probe for a target app (rules + AX) in parallel with selection
    /// retrieval so the popup can apply the result on its first frame. Wired to the popup controller
    /// by the composition root (AppDelegate).
    internal var preparePasteProbe: ((NSRunningApplication, AppPolicyContext) -> Task<Bool?, Never>?)?
    
    private var monitor: Any?
    private var keyDownMonitor: Any?
    internal var debounceTask: Task<Void, Never>?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    internal var mouseHoldTask: Task<Void, Never>?
    private var mouseDownLocation: CGPoint?
    internal var triggeredByHold: Bool = false
    private let settingsStore: SettingsStore

    /// Injectable seams for headless tests; production uses live system state.
    internal var frontmostAppProvider: @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    internal var currentMouseLocation: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    internal var currentCursorProvider: @MainActor () -> CursorClass = { CursorClassifier.current }
    /// Whether the primary button is physically down (fire-time stationarity input); production
    /// reads AppKit live, tests force it true.
    internal var primaryButtonPressed: @MainActor () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    internal var retriever = SelectionRetrievalCoordinator()
    internal var fallbackPasteboard: NSPasteboard = .general
    /// Exclusion predicate over the target app's bundle ID (tests bypass the self-exclusion
    /// pattern, which otherwise matches the test host process itself).
    internal var isExcludedBundle: @MainActor (String?) -> Bool = { bundleID in
        guard let bundleID else { return false }
        return AppFilter.isExcluded(bundleID: bundleID)
    }
    /// Suppression gate consulted at every trigger (and again after every debounce/hold sleep,
    /// since the state can change while the timer runs): while it answers true the monitor
    /// retrieves nothing and delivers nothing, so no selection is even read. Defaults to never suppressed.
    internal var isSuppressed: @MainActor () -> Bool = { false }
    internal var isSuppressedForApp: @MainActor (String?) -> Bool = { _ in false }

    internal func shouldSuppress(for bundleID: String? = nil) -> Bool {
        isSuppressed() || isSuppressedForApp(bundleID ?? frontmostAppProvider()?.bundleIdentifier)
    }
    /// Policy resolution for the target app; tests fix it to `.default` so real user rules
    /// (~/.openclip/rules.json) cannot alter gating or force copy-based strategies mid-test.
    internal var policyResolver: @MainActor (String?) -> AppPolicyContext = { bundleID in
        RuleEngine.shared.resolvePolicies(for: bundleID ?? "")
    }
    
    /// Key codes (ANSI/QWERTY) that signal a selection gesture worth retrieving.
    private static let selectAllKeyCode: UInt16 = 0x00      // kVK_ANSI_A
    /// ⌘L: "select the location" — the address bar in browsers, the current line in editors.
    /// Like ⌘A it selects a whole container, so it is gated the same way downstream.
    private static let selectLocationKeyCode: UInt16 = 0x25 // kVK_ANSI_L
    /// Keys that extend a selection when Shift is held: the four arrows plus the page/line jumps,
    /// which are the same gesture over a bigger stride (⇧⌥→ and ⇧End both extend a selection).
    private static let extendKeyCodes: Set<UInt16> = [
        0x7B, 0x7C, 0x7D, 0x7E,   // left / right / down / up
        0x73, 0x77,               // home / end
        0x74, 0x79                // page up / page down
    ]

    /// Squared drift limits for the hold trigger (points²). A drag beyond `holdDragDisarmSquared`
    /// (5 px) disarms the pending timer outright; the timer fires only while the press is parked
    /// within `holdFireDriftSquared` (2 px) — a slow selection drag must never pop the bar.
    private static let holdDragDisarmSquared: CGFloat = 25.0
    private static let holdFireDriftSquared: CGFloat = 4.0
    /// Delay before the second stationarity sample, catching gestures that begin exactly as the
    /// timer fires (the pointer was parked until that instant).
    private static let holdStationaryConfirmDelayNanoseconds: UInt64 = 90_000_000

    /// Pure fire-time decision (unit-tested): the hold trigger only counts as stationary while the
    /// primary button is down and the pointer sits within `holdFireDriftSquared` of the down point.
    internal static func holdStationary(downPoint: CGPoint?, pointer: CGPoint, buttonPressed: Bool) -> Bool {
        guard buttonPressed else { return false }
        guard let downPoint else { return true }
        let dx = pointer.x - downPoint.x
        let dy = pointer.y - downPoint.y
        return dx * dx + dy * dy <= holdFireDriftSquared
    }
    
    internal init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
    internal func start() {
        guard monitor == nil else { return }
        
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            // Global monitors run on the main thread. Creating `Task { @MainActor in }` here
            // makes the compiler emit an executor-isolation check that crashes in
            // swift_task_isCurrentExecutorWithFlagsImpl after long uptime (known Swift 6 runtime
            // bug); MainActor.assumeIsolated avoids that path.
            MainActor.assumeIsolated {
                self?.handleMouseDown(at: point)
            }
        }

        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.handleMouseDragged(at: point)
            }
        }
        
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let cursor = NSEvent.mouseLocation
            let clickCount = event.clickCount
            MainActor.assumeIsolated {
                self?.handleMouseUp(app: app, cursor: cursor, clickCount: clickCount)
            }
        }
        
        // Keyboard selection gestures (⌘A select-all, ⇧+arrow extend/collapse) trigger the same
        // retrieval path as a mouse drag, so keyboard-only selections surface the popup too.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard Self.isSelectionTrigger(keyCode: event.keyCode, flags: event.modifierFlags) else { return }
                let isSelectAll = Self.isSelectAllKey(keyCode: event.keyCode, flags: event.modifierFlags)
                self?.handleSelectionTrigger(isSelectAll: isSelectAll)
            }
        }
    }
    
    internal func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        mouseHoldTask?.cancel()
        mouseHoldTask = nil
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let mouseDownMonitor = mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let mouseDragMonitor = mouseDragMonitor {
            NSEvent.removeMonitor(mouseDragMonitor)
            self.mouseDragMonitor = nil
        }
        if let keyDownMonitor = keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }
    
    // MARK: - Trigger detection
    
    /// True when a key event is a selection gesture OpenClip should retrieve: ⌘A (select all),
    /// ⌘L (select the address bar / current line), or an extend key with Shift held (⇧/⌥⇧/⌘⇧ +
    /// arrow, Home, End, Page Up, Page Down). The whole-container gestures require the exact
    /// `.command` set; extend gestures fire whenever `.shift` is held with optional
    /// `.option`/`.command`, so plain typing and unrelated shortcuts still don't match.
    /// Persistent/non-gesture flags (`.capsLock`
    /// is held in every keyDown's modifierFlags while caps lock is engaged; `.function`, `.numericPad`,
    /// `.help` are device/hardware bits) are stripped before comparing — Home/End/Page keys carry
    /// `.function`, so that stripping is what lets them match at all.
    internal static func isSelectionTrigger(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let gestureFlags = normalizedGestureFlags(flags)
        if gestureFlags == .command {
            return keyCode == selectAllKeyCode || keyCode == selectLocationKeyCode
        }
        if gestureFlags.contains(.shift) && gestureFlags.isSubset(of: [.shift, .option, .command]) {
            return extendKeyCodes.contains(keyCode)
        }
        return false
    }

    /// True for the whole-container select gestures — the exact ⌘A (select all) and ⌘L (select the
    /// location / line). Both hand the retrieval gate the same "this selects everything in the
    /// focused container" signal, so a row selection in Finder/Mail is refused while text is not.
    internal static func isSelectAllKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let gestureFlags = normalizedGestureFlags(flags)
        guard gestureFlags == .command else { return false }
        return keyCode == selectAllKeyCode || keyCode == selectLocationKeyCode
    }

    /// Strips the flags that are never part of a gesture: `.capsLock` rides along in every keyDown
    /// while caps lock is engaged, and `.function`/`.numericPad`/`.help` are device bits.
    private static func normalizedGestureFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad, .help])
    }
    
    // MARK: - Event handling

    internal func handleMouseDown(at point: CGPoint) {
        mouseDownLocation = point
        triggeredByHold = false
        mouseHoldTask?.cancel()

        guard settingsStore.get(.pauseUntilTimestamp) <= Date().timeIntervalSince1970 else { return }
        guard !shouldSuppress() else { return }
        guard settingsStore.get(.isMouseHoldEnabled) else { return }
        let holdDuration = settingsStore.get(.mouseHoldDuration)
        guard holdDuration > 0 else { return }

        mouseHoldTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            // Stationarity gate #1: a slow drag start must not pop the bar over an unfinished
            // selection — require the press to be genuinely parked near the down point.
            var currentPoint = currentMouseLocation()
            guard Self.holdStationary(downPoint: self.mouseDownLocation, pointer: currentPoint, buttonPressed: self.primaryButtonPressed()) else { return }

            // Stationarity gate #2: re-sample shortly after, catching gestures that begin exactly
            // as the timer fires (the pointer was parked until that instant).
            do {
                try await Task.sleep(nanoseconds: Self.holdStationaryConfirmDelayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            currentPoint = currentMouseLocation()
            guard Self.holdStationary(downPoint: self.mouseDownLocation, pointer: currentPoint, buttonPressed: self.primaryButtonPressed()) else { return }

            guard let app = frontmostAppProvider() else { return }
            guard !self.shouldSuppress(for: app.bundleIdentifier) else { return }
            if isExcludedBundle(app.bundleIdentifier) {
                return
            }

            self.triggeredByHold = true
            // A fired hold that exits WITHOUT delivering must not swallow this press's release
            // path: clear the trigger so mouse-up falls through to the ordinary drag/click
            // selection flow ("press, pause a beat, then drag-select" depends on this).
            var delivered = false
            defer { if !delivered { self.triggeredByHold = false } }

            let policy = self.policyResolver(app.bundleIdentifier)
            if policy.disabled || policy.hotkeyOnly {
                return
            }
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)

            var retrievedText = ""
            var selectionBounds: CGRect? = nil
            var selectionHTML: String?
            var selectionRTF: String?
            var isClipboardFallback = false

            let cursor = self.currentCursorProvider()
            let (result, isEditable) = await retriever.retrieveDetails(
                for: appIdentity,
                policy: policy,
                cursor: cursor,
                allowCopyFallback: false
            )
            if let result {
                retrievedText = result.text
                selectionBounds = result.bounds
                selectionHTML = result.html
                selectionRTF = result.rtf
            }

            let canPaste = await probeTask?.value

            // If no text was actively selected, only inherit clipboard content in an editable text context (AX text control or I-beam cursor and paste allowed)
            if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let isEditableContext = isEditable || cursor == .beam
                if isEditableContext && canPaste != false,
                   let clipboard = fallbackPasteboard.string(forType: .string),
                   !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Log.selection.debug("monitor: hold falling back to clipboard for \(appIdentity.bundleIdentifier ?? "unknown", privacy: .public)")
                    retrievedText = clipboard
                    isClipboardFallback = true
                } else {
                    Log.selection.debug("monitor: hold clipboard fallback skipped for \(appIdentity.bundleIdentifier ?? "unknown", privacy: .public); isEditable=\(isEditable), cursor=\(cursor.rawValue, privacy: .public), canPaste=\(String(describing: canPaste))")
                }
            }

            guard !Task.isCancelled else { return }
            guard TextSanitizer.isSubstantial(retrievedText),
                  retrievedText.utf8.count <= Constants.maxTextLength else { return }

            let context = SelectionContext(
                text: retrievedText,
                sourceApp: appIdentity,
                cursorPosition: currentPoint,
                mouseDownLocation: self.mouseDownLocation,
                selectionBounds: selectionBounds,
                timestamp: Date(),
                appPolicy: policy,
                isClipboardFallback: isClipboardFallback,
                html: selectionHTML,
                rtf: selectionRTF
            )
            guard !Task.isCancelled else { return }
            guard !self.shouldSuppress(for: appIdentity.bundleIdentifier) else { return }
            delivered = true
            self.onSelection?(context, canPaste)
        }
    }

    internal func handleMouseDragged(at point: CGPoint) {
        guard let downPoint = mouseDownLocation else { return }
        let dx = point.x - downPoint.x
        let dy = point.y - downPoint.y
        if (dx * dx + dy * dy) > Self.holdDragDisarmSquared {
            // A drag is now the gesture in progress: disarm an unfired timer, and clear the hold
            // flag so a fired-but-unproductive hold cannot suppress this press's legitimate
            // selection delivery on release. A fired task that is mid-delivery keeps running —
            // cancelling it here would kill the popup for normal-speed press-drag gestures.
            if !triggeredByHold {
                mouseHoldTask?.cancel()
            }
            mouseHoldTask = nil
            triggeredByHold = false
        }
    }

    internal func handleMouseUp(app: NSRunningApplication, cursor: CGPoint, clickCount: Int) {
        // Decide from pre-mutation state: once the hold timer has fired, `mouseHoldTask` is no
        // longer a pending timer but a delivery job whose AX retrieval + paste probe typically
        // outlasts the physical hold — cancelling it here killed every normal-speed release
        // mid-flight, so a fired hold owns its delivery to completion.
        let wasHold = triggeredByHold
        triggeredByHold = false

        let downPoint = mouseDownLocation
        mouseDownLocation = nil

        // If hold-to-popup delivered (or is delivering) this press's popup, don't duplicate on release.
        guard !wasHold else { return }

        // The hold never fired: ordinary click/drag press cycle — stop the pending timer.
        mouseHoldTask?.cancel()
        mouseHoldTask = nil

        debounceTask?.cancel()

        guard settingsStore.get(.pauseUntilTimestamp) <= Date().timeIntervalSince1970 else { return }
        guard !shouldSuppress(for: app.bundleIdentifier) else { return }

        debounceTask = Task { @MainActor in
            guard !self.shouldSuppress(for: app.bundleIdentifier) else { return }
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = self.policyResolver(app.bundleIdentifier)
            if policy.disabled || policy.hotkeyOnly {
                return
            }
            
            // Measure drag distance for click filtering
            var isDragOrMultiClick = clickCount >= 2
            if !isDragOrMultiClick, let downPoint {
                let dx = cursor.x - downPoint.x
                let dy = cursor.y - downPoint.y
                isDragOrMultiClick = (dx * dx + dy * dy) > 9.0 // > 3px movement
            }
            guard isDragOrMultiClick else { return }
            
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current
            )
            if Task.isCancelled { return }
            await self.deliverSelection(
                result: result,
                appIdentity: appIdentity,
                policy: policy,
                cursor: cursor,
                mouseDownLocation: downPoint,
                probeTask: probeTask
            )
        }
    }
    
    /// Keyboard selection gesture: retrieve under the frontmost app resolved *after* the debounce
    /// (a ⌘A/⇧+arrow in one app followed by a switch during the debounce window must target the
    /// now-frontmost app). `isSelectAll` marks a whole-container gesture (⌘A / ⌘L), which retrieval
    /// refuses on a row/list container (row selection in Finder/Mail/table views).
    internal func handleSelectionTrigger(isSelectAll: Bool) {
        debounceTask?.cancel()
        guard settingsStore.get(.pauseUntilTimestamp) <= Date().timeIntervalSince1970 else { return }
        guard !shouldSuppress() else { return }
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(Constants.keyboardSelectionDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            if Task.isCancelled { return }

            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            guard !self.shouldSuppress(for: app.bundleIdentifier) else { return }

            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = self.policyResolver(app.bundleIdentifier)
            if policy.disabled || policy.hotkeyOnly {
                return
            }
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current,
                isSelectAll: isSelectAll
            )
            if Task.isCancelled { return }
            let anchor = Self.keyboardAnchor(
                bounds: result?.bounds,
                isSelectAll: isSelectAll,
                mouseLocation: NSEvent.mouseLocation
            )
            await self.deliverSelection(
                result: result,
                appIdentity: appIdentity,
                policy: policy,
                cursor: anchor,
                mouseDownLocation: nil,
                probeTask: probeTask
            )
        }
    }

    /// Screen anchor for a keyboard-triggered selection popup (pure, unit-tested).
    ///
    /// Arrow-key selections anchor on the selection's accessibility bounds so the popup appears
    /// next to the selected text even when the mouse rests elsewhere. A ⌘A select-all spans the
    /// whole document, so its top-left corner is meaningless as an anchor — the popup follows the
    /// pointer instead, matching where the user is working. The pointer fallback also applies
    /// when there are no usable bounds or the converted anchor lands off-screen.
    internal static func keyboardAnchor(bounds: CGRect?, isSelectAll: Bool, mouseLocation: CGPoint) -> CGPoint {
        if !isSelectAll, let bounds {
            let anchor = cocoaPoint(fromAXPoint: CGPoint(x: bounds.minX, y: bounds.minY))
            if NSScreen.screens.contains(where: { $0.frame.contains(anchor) }) {
                return anchor
            }
        }
        return mouseLocation
    }

    /// Converts an accessibility-coordinate point into Cocoa screen coordinates. AX uses a global
    /// top-left origin on the *primary* display (the screen at `.zero`, `NSScreen.screens[0]`) —
    /// not `NSScreen.main`, which tracks keyboard focus and differs from primary on multi-display
    /// setups.
    private static func cocoaPoint(fromAXPoint point: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
    }
    
    /// Shared post-retrieval assembly: build the length-gated SelectionContext and notify
    /// `onSelection` with the paste-probe result. Used by both the mouse and keyboard paths.
    private func deliverSelection(
        result: TextResult?,
        appIdentity: AppIdentity,
        policy: AppPolicyContext,
        cursor: CGPoint,
        mouseDownLocation: CGPoint?,
        probeTask: Task<Bool?, Never>?
    ) async {
        guard !Task.isCancelled else { return }
        guard let result,
              TextSanitizer.isSubstantial(result.text),
              result.text.utf8.count <= Constants.maxTextLength else { return }
        let context = SelectionContext(
            text: result.text,
            sourceApp: appIdentity,
            cursorPosition: cursor,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: result.bounds,
            timestamp: Date(),
            appPolicy: policy,
            html: result.html,
            rtf: result.rtf
        )
        let canPaste = await probeTask?.value
        guard !Task.isCancelled else { return }
        self.onSelection?(context, canPaste)
    }
}