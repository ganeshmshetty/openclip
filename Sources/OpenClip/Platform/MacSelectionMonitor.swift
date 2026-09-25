// MacSelectionMonitor.swift
// OpenClip
//
// Monitors macOS mouse and keyboard events to detect text selection actions and trigger OpenClip
// popup presentation. Every trigger passes the `isSuppressed` gate first (wired to the popup's
// modal result card by AppDelegate), so while that card is open no selection is read at all.
import AppKit
import CoreGraphics
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
    public internal(set) var latestSelection: (context: SelectionContext, canPaste: Bool?)?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    internal var mouseHoldTask: Task<Void, Never>?
    private var mouseDownLocation: CGPoint?
    /// Whether the press that started the current gesture landed on system chrome. Gate on this
    /// (the press), not on where the pointer is released: a drag that begins in a window and
    /// overshoots onto the menu bar or Dock is still a selection, while one that begins on chrome is not.
    internal var mouseDownWasSystemChrome: Bool = false
    internal var triggeredByHold: Bool = false
    private let settingsStore: SettingsStore

    /// Injectable seams for headless tests; production uses live system state.
    internal var frontmostAppProvider: @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    internal var currentMouseLocation: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    internal var currentCursorProvider: @MainActor () -> CursorClass = { CursorClassifier.current.asCore }
    /// Whether the primary button is physically down (fire-time stationarity input); production
    /// reads AppKit live, tests force it true.
    internal var primaryButtonPressed: @MainActor () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    internal var now: @MainActor () -> Date = { Date() }
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
    /// Whether `point` sits on on-screen system chrome (the menu bar or Dock). Injectable so tests
    /// can exercise the gesture gating against a fixed geometry.
    internal var isSystemChromeAt: @MainActor (CGPoint) -> Bool = { MacSelectionMonitor.isSystemChromeLocation($0) }
    /// Whether the element under `point` is, or sits inside, an editable text control. Anchors the
    /// hold's clipboard fallback to the field actually under the finger, rather than whichever
    /// element happens to be focused — a hold on a window background must not inherit the clipboard
    /// just because a text field elsewhere is focused. Inert under XCTest; inject for tests.
    internal var isPressOverEditableText: @MainActor (CGPoint) -> Bool = { MacSelectionMonitor.hitTestIsEditableText(at: $0) }
    /// Overlay gate: true when a *foreign* window (a screenshot/annotation tool's full-screen picker,
    /// a non-activating HUD) sits above the frontmost app at `point`. The automatic path stands down
    /// while one is up, because copy-based retrieval posts a real ⌘C that lands on that overlay's key
    /// window — firing the overlay's own Copy shortcut and tearing it down — rather than on the app
    /// OpenClip meant to read. The explicit hotkey path stays exempt: the user asked for that read.
    internal var isOverlayPresent: @MainActor (CGPoint) -> Bool = { point in
        // Headless tests must not depend on the live window server; the pure gate is unit-tested directly.
        guard NSClassFromString("XCTestCase") == nil else { return false }
        return CopyTriggerGate.isForeignOverlayPresent(at: point)
    }

    internal func shouldSuppress(for bundleID: String? = nil) -> Bool {
        isSuppressed() || isSuppressedForApp(bundleID ?? frontmostAppProvider()?.bundleIdentifier)
    }
    /// Policy resolution for the target app; tests fix it to `.default` so real user rules
    /// (~/.openclip/rules.json) cannot alter gating or force copy-based strategies mid-test.
    internal var policyResolver: @MainActor (String?) -> AppPolicyContext = { bundleID in
        RuleEngine.shared.resolvePolicies(for: bundleID ?? "")
    }
    
    // Delegated to OpenSelectionMonitor
    internal static let selectAllKeyCode: UInt16 = OpenSelectionMonitor.selectAllKeyCode
    internal static let selectLocationKeyCode: UInt16 = OpenSelectionMonitor.selectLocationKeyCode
    internal static let extendKeyCodes: Set<UInt16> = OpenSelectionMonitor.extendKeyCodes
    internal static let holdDragDisarmSquared: CGFloat = OpenSelectionMonitor.holdDragDisarmSquared
    internal static let holdFireDriftSquared: CGFloat = OpenSelectionMonitor.holdFireDriftSquared
    internal static let dragThresholdSquared: CGFloat = OpenSelectionMonitor.dragThresholdSquared
    private static let holdStationaryConfirmDelayNanoseconds: UInt64 = 90_000_000

    internal static func holdStationary(downPoint: CGPoint?, pointer: CGPoint, buttonPressed: Bool) -> Bool {
        OpenSelectionMonitor.holdStationary(downPoint: downPoint, pointer: pointer, buttonPressed: buttonPressed)
    }

    internal static func isSystemChromeLocation(_ point: CGPoint) -> Bool {
        OpenSelectionMonitor.isSystemChromeLocation(point)
    }

    /// Roles that mean "the pointer is over an editable text field" for the hold's paste fallback.
    private static let editableTextRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    /// AX hit-test at `point` (Cocoa screen coordinates), walking a few ancestors for an editable
    /// text-control role. A window background, toolbar, or static text resolves to something else,
    /// so a hold there no longer inherits the clipboard from a focused field. Inert under XCTest so
    /// tests drive the decision through the `isPressOverEditableText` seam. Best-effort: some web
    /// editors (CodeMirror) do not resolve to a text control here, which is why the I-beam cursor
    /// is checked alongside it.
    internal static func hitTestIsEditableText(at point: CGPoint) -> Bool {
        guard NSClassFromString("XCTestCase") == nil else { return false }
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        // This runs on the main actor inside the hold task, so an unresponsive target app must not
        // freeze the popup and event monitors. Cap every AX round-trip at `axReadTimeout` instead
        // of letting it wait out the multi-second default messaging timeout.
        let timeout = Float(Constants.axReadTimeout)
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &element) == .success,
              let start = element else { return false }

        var current: AXUIElement? = start
        var depth = 0
        while let el = current, depth < 6 {
            AXUIElementSetMessagingTimeout(el, timeout)
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, editableTextRoles.contains(role) {
                return true
            }
            var parentRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef)
            current = parentRef.map { $0 as! AXUIElement }
            depth += 1
        }
        return false
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
                self?.handleKeyDown(keyCode: event.keyCode, flags: event.modifierFlags)
            }
        }
    }

    internal func handleKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        if Self.isSelectionTrigger(keyCode: keyCode, flags: flags) {
            let isSelectAll = Self.isSelectAllKey(keyCode: keyCode, flags: flags)
            handleSelectionTrigger(isSelectAll: isSelectAll)
        } else if Self.isSelectionClearingKey(keyCode: keyCode, flags: flags) {
            debounceTask?.cancel()
            debounceTask = nil
            clearSelection()
        }
    }
    
    public func clearSelection() {
        latestSelection = nil
    }

    public func currentSelection(for bundleID: String?) async -> (context: SelectionContext, canPaste: Bool?)? {
        if let debounceTask {
            _ = await debounceTask.value
        }
        return synchronousSelection(for: bundleID)
    }

    public func synchronousSelection(for bundleID: String?) -> (context: SelectionContext, canPaste: Bool?)? {
        guard let latest = latestSelection,
              let targetBundle = bundleID,
              latest.context.sourceApp.bundleIdentifier == targetBundle else {
            return nil
        }
        guard now().timeIntervalSince(latest.context.timestamp) <= Constants.selectionMaxAge else {
            latestSelection = nil
            return nil
        }
        return latest
    }

    internal func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        mouseHoldTask?.cancel()
        mouseHoldTask = nil
        clearSelection()
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
    
    // MARK: - Trigger detection (delegated to OpenSelectionMonitor)

    internal static func isSelectionTrigger(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        OpenSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: flags)
    }

    internal static func isSelectAllKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        OpenSelectionMonitor.isSelectAllKey(keyCode: keyCode, flags: flags)
    }

    internal static func isSelectionClearingKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        OpenSelectionMonitor.isSelectionClearingKey(keyCode: keyCode, flags: flags)
    }
    
    // MARK: - Event handling

    internal func handleMouseDown(at point: CGPoint) {
        if isSystemChromeAt(point) {
            mouseDownLocation = nil
            mouseDownWasSystemChrome = true
            return
        }
        mouseDownWasSystemChrome = false
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
            var selectionFlavors: [RichPasteboardFlavor] = []
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
                selectionFlavors = result.flavors
            }

            let canPaste = await probeTask?.value

            // If no text was actively selected, only inherit clipboard content when the press is
            // actually over editable text: either an I-beam sits at the press point, or an AX
            // hit-test resolves it to a text control. Trusting the *focused* element instead let a
            // hold on a window background / toolbar / static text paste the clipboard just because
            // a field elsewhere was focused. The I-beam is kept because some web editors
            // (CodeMirror) do not resolve to a text control through the hit-test.
            if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let isEditableContext = cursor == .beam || isPressOverEditableText(point)
                if isEditableContext && canPaste != false,
                   let clipboard = fallbackPasteboard.string(forType: .string),
                   !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Log.selection.debug("monitor: hold falling back to clipboard for \(appIdentity.bundleIdentifier ?? "unknown", privacy: .public); cursor=\(cursor.rawValue, privacy: .public)")
                    retrievedText = clipboard
                    isClipboardFallback = true
                } else {
                    Log.selection.debug("monitor: hold clipboard fallback skipped for \(appIdentity.bundleIdentifier ?? "unknown", privacy: .public); pressOverEditable=\(isEditableContext, privacy: .public), isEditable=\(isEditable, privacy: .public), cursor=\(cursor.rawValue, privacy: .public), canPaste=\(String(describing: canPaste), privacy: .public)")
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
                rtf: selectionRTF,
                flavors: selectionFlavors
            )
            guard !Task.isCancelled else { return }
            guard !self.shouldSuppress(for: appIdentity.bundleIdentifier) else { return }
            delivered = true
            latestSelection = (context, canPaste)
            prewarmInlineActions(for: context)
            await InlineResultEvaluator.shared.awaitPrewarmed(timeout: 0.025)
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

        let wasSystemChrome = mouseDownWasSystemChrome
        mouseDownWasSystemChrome = false

        let downPoint = mouseDownLocation
        mouseDownLocation = nil

        // If hold-to-popup delivered (or is delivering) this press's popup, don't duplicate on release.
        guard !wasHold else { return }

        // The hold never fired: ordinary click/drag press cycle — stop the pending timer.
        mouseHoldTask?.cancel()
        mouseHoldTask = nil

        debounceTask?.cancel()

        // Gate on where the press landed, not where the pointer came up: a drag that begins inside
        // a window and overshoots onto the menu bar or Dock (the usual way of selecting text that
        // sits against a screen edge) is still a legitimate selection. An interaction that *begins*
        // on chrome is not.
        guard !wasSystemChrome else {
            clearSelection()
            return
        }

        guard settingsStore.get(.pauseUntilTimestamp) <= Date().timeIntervalSince1970 else { return }
        guard !shouldSuppress(for: app.bundleIdentifier) else { return }

        // Measure drag distance for click filtering
        var isDragOrMultiClick = clickCount >= 2
        if !isDragOrMultiClick, let downPoint {
            let dx = cursor.x - downPoint.x
            let dy = cursor.y - downPoint.y
            isDragOrMultiClick = (dx * dx + dy * dy) > Self.dragThresholdSquared // > 5pt movement
        }
        guard isDragOrMultiClick else {
            clearSelection()
            return
        }

        debounceTask = Task { @MainActor in
            guard !self.shouldSuppress(for: app.bundleIdentifier) else { return }
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = self.policyResolver(app.bundleIdentifier)
            if policy.disabled {
                return
            }
            
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            // Keep monitoring (so `latestSelection` stays warm for ⌥⌘C) but never post a synthetic
            // ⌘C when:
            // 1. "Appear Automatically" is disabled (passive background caching must stay non-invasive)
            // 2. The app has `hotkeyOnly` policy
            // 3. A foreign overlay owns the key window
            let isAutoEnabled = self.settingsStore.get(.isAppEnabled)
            let allowCopyFallback = isAutoEnabled && !policy.hotkeyOnly && !self.isOverlayPresent(cursor)
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current.asCore,
                allowCopyFallback: allowCopyFallback
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

            guard let app = self.frontmostAppProvider() else { return }
            guard !self.shouldSuppress(for: app.bundleIdentifier) else { return }

            if self.isExcludedBundle(app.bundleIdentifier) {
                return
            }
            
            let policy = self.policyResolver(app.bundleIdentifier)
            if policy.disabled {
                return
            }
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            // Same overlay guard as the mouse-up path: keep caching, but never post a synthetic ⌘C
            // into another app's key window (see the mouse-up comment for the mechanism).
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: self.currentCursorProvider(),
                isSelectAll: isSelectAll,
                allowCopyFallback: !self.isOverlayPresent(self.currentMouseLocation()),
                requireCopyEvidence: false
            )
            if Task.isCancelled { return }
            let anchor = Self.keyboardAnchor(
                bounds: result?.bounds,
                isSelectAll: isSelectAll,
                mouseLocation: self.currentMouseLocation()
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

    /// Screen anchor for a keyboard-triggered selection popup (delegated to OpenSelectionMonitor).
    internal static func keyboardAnchor(bounds: CGRect?, isSelectAll: Bool, mouseLocation: CGPoint) -> CGPoint {
        OpenSelectionMonitor.keyboardAnchor(bounds: bounds, isSelectAll: isSelectAll, mouseLocation: mouseLocation)
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
              result.text.utf8.count <= Constants.maxTextLength else {
            clearSelection()
            return
        }
        let context = SelectionContext(
            text: result.text,
            sourceApp: appIdentity,
            cursorPosition: cursor,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: result.bounds,
            timestamp: now(),
            appPolicy: policy,
            html: result.html,
            rtf: result.rtf,
            flavors: result.flavors
        )
        prewarmInlineActions(for: context)
        let canPaste = await probeTask?.value
        guard !Task.isCancelled else { return }
        latestSelection = (context, canPaste)
        await InlineResultEvaluator.shared.awaitPrewarmed(timeout: 0.025)
        // "Appear Automatically" (isAppEnabled) is the global form of the per-app `hotkeyOnly`
        // rule: it suppresses the passive auto-show for mouse-release and keyboard selections
        // while leaving the explicit hold gesture (delivered in `handleMouseDown`, which never
        // routes through here) and the ⌥⌘C hotkey independent. Monitoring still runs, so
        // `latestSelection` stays warm for the hotkey.
        if !policy.hotkeyOnly, self.settingsStore.get(.isAppEnabled) {
            self.onSelection?(context, canPaste)
        }
    }

    private func prewarmInlineActions(for context: SelectionContext) {
        let actionContext = ActionContext(selection: context, modifiers: [])
        let catalog = ActionCoordinator.shared.searchCatalog(for: actionContext)
        PopupSearchView.prewarmIndex(catalog: catalog)
        let inlineActions = catalog.filter { $0.chrome.isInlineResult }
        if !inlineActions.isEmpty {
            InlineResultEvaluator.shared.prewarm(actions: inlineActions, context: actionContext)
        }
    }
}
