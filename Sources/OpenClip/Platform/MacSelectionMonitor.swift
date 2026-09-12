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
    public internal(set) var latestSelection: (context: SelectionContext, canPaste: Bool?)?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    internal var mouseHoldTask: Task<Void, Never>?
    private var mouseDownLocation: CGPoint?
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
    
    internal var innerMonitor: OpenSelectionMonitor

    internal init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        self.innerMonitor = OpenSelection.monitor()
    }
    
    internal func start() {
        guard monitor == nil else { return }
        innerMonitor.start()
        
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
        innerMonitor.stop()
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
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current.asCore
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
            if policy.disabled {
                return
            }
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            let result = await retriever.retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current.asCore,
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
            rtf: result.rtf
        )
        prewarmInlineActions(for: context)
        let canPaste = await probeTask?.value
        guard !Task.isCancelled else { return }
        latestSelection = (context, canPaste)
        await InlineResultEvaluator.shared.awaitPrewarmed(timeout: 0.025)
        if !policy.hotkeyOnly {
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