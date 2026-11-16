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
    internal private(set) var selectionGeneration: UInt64? = 0
    internal private(set) var lastReadResponse: SelectionTriggerResponse?
    internal var onReadOutcome: ((SelectionTriggerResponse) -> Void)?

    private func recordRead(_ response: SelectionTriggerResponse) {
        lastReadResponse = response
        onReadOutcome?(response)
        if let traceID = response.traceID, response.status != .selection {
            Log.selection.debug("[Trace#\(traceID, privacy: .public)] monitor delivery outcome: \(response.status.rawValue, privacy: .public)")
        }
    }

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
    private var appActivationObserver: NSObjectProtocol?
    internal var mouseHoldTask: Task<Void, Never>?
    private var mouseDownLocation: CGPoint?
    /// Preserve text context when a selection drag ends over blank space and the cursor changes.
    private var mouseDownCursor: CursorClass?
    private var mouseDownWindow: SelectionGestureWindow?
    /// Whether the press that started the current gesture landed on system chrome. Gate on this
    /// (the press), not on where the pointer is released: a drag that begins in a window and
    /// overshoots onto the menu bar or Dock is still a selection, while one that begins on chrome is not.
    internal var mouseDownWasSystemChrome: Bool = false
    internal var triggeredByHold: Bool = false
    private var selectionSourceApp: NSRunningApplication?
    private let settingsStore: SettingsStore

    /// Injectable seams for headless tests; production uses live system state.
    internal var frontmostAppProvider: @MainActor () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    internal var currentMouseLocation: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    internal var currentCursorProvider: @MainActor () -> CursorClass = { CursorClassifier.current.asCore }
    /// Whether the primary button is physically down (fire-time stationarity input); production
    /// reads AppKit live, tests force it true.
    internal var primaryButtonPressed: @MainActor () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    internal var now: @MainActor () -> Date = { Date() }
    internal lazy var retriever = SelectionRetrievalCoordinator(configuration: .default, detailedCopyCapture: { [weak self] request in
        guard let self else { return SelectionReadResponse(status: .cancelled) }
        return await self.captureAutomaticCopyResponse(request)
    })
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
    internal var windowAtPoint: @MainActor (CGPoint) -> SelectionGestureWindow? = { SelectionGestureWindow.at($0) }
    internal var windowFrame: @MainActor (CGWindowID) -> CGRect? = { SelectionGestureWindow.currentFrame(for: $0) }
    internal var requestAppAccessibility: @MainActor (NSRunningApplication?) -> Void = { app in
        guard NSClassFromString("XCTestCase") == nil else { return }
        ElectronAccessibilityEnabler.shared.enableIfNeeded(for: app)
    }
    internal var gestureScreens: @MainActor () -> SelectionGestureLocality.ScreenLayout = { .current }
    internal var isPressOnWindowChrome: @MainActor (CGPoint, pid_t) async -> Bool = { point, pid in
        guard NSClassFromString("XCTestCase") == nil else { return false }
        let screenTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.screens.first?.frame.maxY ?? 0
        return await SelectionGestureTargetProbe.default.isWindowChrome(
            at: CGPoint(x: point.x, y: screenTop - point.y), pid: pid)
    }
    /// Whether the press at `point` is over editable text, decided structurally (AX hit-test plus
    /// focused-element correlation), never by cursor shape. Anchors the hold's clipboard fallback
    /// to the field actually under the finger, rather than whichever element happens to be focused —
    /// a hold on a window background must not inherit the clipboard just because a text field
    /// elsewhere is focused. Inert under XCTest; inject for tests.
    internal var isPressOverEditableText: @MainActor (CGPoint, pid_t) async -> Bool = { point, pid in
        await MacSelectionMonitor.pressIsOverEditableText(at: point, pid: pid)
    }
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
    internal var policyResolver: @MainActor (AppIdentity) -> AppPolicyContext = { identity in
        RuleEngine.shared.resolvePolicies(for: identity)
    }
    
    // Delegated to OpenSelectionMonitor
    internal static let selectAllKeyCode: UInt16 = OpenSelectionMonitor.selectAllKeyCode
    internal static let selectLocationKeyCode: UInt16 = OpenSelectionMonitor.selectLocationKeyCode
    internal static let extendKeyCodes: Set<UInt16> = OpenSelectionMonitor.extendKeyCodes
    internal static let holdDragDisarmSquared: CGFloat = OpenSelectionMonitor.holdDragDisarmSquared
    internal static let holdFireDriftSquared: CGFloat = OpenSelectionMonitor.holdFireDriftSquared
    internal static let dragThresholdSquared: CGFloat = OpenSelectionMonitor.dragThresholdSquared
    private static let holdStationaryConfirmDelayNanoseconds: UInt64 = 90_000_000
    /// How long a multi-click waits for AppKit to apply a native window zoom/resize before its
    /// press is treated as a text gesture. This is a window-geometry guard, not a triple-click
    /// guard: a double-click read no longer waits out the system multi-click interval, and a
    /// third press either cancels it while still in flight or replaces the visible word popup.
    internal static let defaultMultiClickWindowSettleNanoseconds: UInt64 = 50_000_000
    /// Injectable so tests can drive multi-click delivery without a wall-clock wait.
    internal var multiClickWindowSettleNanoseconds = MacSelectionMonitor.defaultMultiClickWindowSettleNanoseconds

    internal static func holdStationary(downPoint: CGPoint?, pointer: CGPoint, buttonPressed: Bool) -> Bool {
        OpenSelectionMonitor.holdStationary(downPoint: downPoint, pointer: pointer, buttonPressed: buttonPressed)
    }

    internal static func isSystemChromeLocation(_ point: CGPoint) -> Bool {
        OpenSelectionMonitor.isSystemChromeLocation(point)
    }

    /// Capture screen geometry on the main actor, then run the deadline-bounded AX lookup
    /// off the UI thread. The PID belongs to the hold's source app, not a later frontmost app.
    internal static func pressIsOverEditableText(at point: CGPoint, pid: pid_t) async -> Bool {
        guard NSClassFromString("XCTestCase") == nil else { return false }
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return await SelectionEditabilityProbe.default.isEditable(at: axPoint, pid: pid)
    }

    /// The classification itself, free of AX and of screen state so it is directly testable: the press
    /// counts as over editable text when the hit-test found a text control, or when a focused text
    /// control's frame actually covers the press (within the supplied tolerance).
    internal static func pressIsOverEditableText(
        hitIsEditableControl: Bool,
        focusedIsEditableControl: Bool,
        focusedFrame: CGRect?,
        pressAXPoint: CGPoint,
        tolerance: CGFloat = 12
    ) -> Bool {
        SelectionEditabilityProbe.isEditable(
            hitIsEditableControl: hitIsEditableControl,
            focusedIsEditableControl: focusedIsEditableControl,
            focusedFrame: focusedFrame,
            pressAXPoint: pressAXPoint,
            tolerance: tolerance
        )
    }

    internal init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
    internal func start() {
        guard monitor == nil else { return }
        requestAppAccessibility(frontmostAppProvider())

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handleApplicationActivation(app)
            }
        }

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
        selectionGeneration = (selectionGeneration ?? 0) &+ 1
        latestSelection = nil
    }

    public func currentSelection(for bundleID: String?) async -> (context: SelectionContext, canPaste: Bool?)? {
        if let debounceTask {
            _ = await debounceTask.value
        }
        return synchronousSelection(for: bundleID)
    }

    public func currentSelection(for app: AppIdentity) async -> (context: SelectionContext, canPaste: Bool?)? {
        if let debounceTask {
            _ = await debounceTask.value
        }
        return synchronousSelection(for: app)
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

    public func synchronousSelection(for app: AppIdentity) -> (context: SelectionContext, canPaste: Bool?)? {
        guard let latest = latestSelection else { return nil }
        if let targetPID = app.processIdentifier, let sourcePID = latest.context.sourceApp.processIdentifier {
            guard targetPID == sourcePID else { return nil }
        }
        guard app.isSameApp(as: latest.context.sourceApp) else { return nil }
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
        selectionSourceApp = nil
        mouseDownWindow = nil
        mouseDownCursor = nil
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
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

    /// A new press or application activation invalidates any earlier automatic copy attempt.
    internal func cancelPendingSelection() {
        debounceTask?.cancel()
        debounceTask = nil
        mouseHoldTask?.cancel()
        mouseHoldTask = nil
        triggeredByHold = false
        selectionSourceApp = nil
        mouseDownCursor = nil
        clearSelection()
    }

    internal func handleApplicationActivation(_ app: NSRunningApplication?) {
        guard let frontmost = frontmostAppProvider() else {
            cancelPendingSelection()
            return
        }
        let activated = app ?? frontmost
        requestAppAccessibility(activated)
        // Ignore queued notifications for an app that is no longer frontmost, and our own
        // popup activation. A real switch to a different source always invalidates the read.
        guard activated.processIdentifier == frontmost.processIdentifier else { return }
        guard activated.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard activated.processIdentifier != selectionSourceApp?.processIdentifier else { return }
        cancelPendingSelection()
    }

    private func isSelectionSourceActive(_ app: NSRunningApplication) -> Bool {
        guard !Task.isCancelled, !shouldSuppress(for: app.bundleIdentifier),
              let frontmost = frontmostAppProvider() else { return false }
        return frontmost.processIdentifier == app.processIdentifier
    }

    /// The package protects focus changes during capture. Also validate the original source
    /// before capture starts, since AX retrieval may have yielded while another app activated.
    internal func captureAutomaticCopy(
        _ request: CopyRequest,
        capture: @MainActor (CopyRequest) async -> SelectionResult? = { request in
            await AutomaticCopyCapture.capture(request: request)
        }
    ) async -> SelectionResult? {
        guard let source = selectionSourceApp, isSelectionSourceActive(source) else { return nil }
        return await capture(request)
    }

    internal func captureAutomaticCopyResponse(_ request: CopyRequest) async -> SelectionReadResponse {
        if Task.isCancelled { return .init(status: .cancelled) }
        guard let source = selectionSourceApp, isSelectionSourceActive(source) else {
            return .init(status: isSuppressed() ? .copyBlocked : .targetChanged)
        }
        return await AutomaticCopyCapture.captureResponse(request: request)
    }

    internal func handleMouseDown(at point: CGPoint) {
        cancelPendingSelection()
        selectionSourceApp = frontmostAppProvider()
        requestAppAccessibility(selectionSourceApp)
        mouseDownWindow = nil
        if isSystemChromeAt(point) {
            mouseDownLocation = nil
            mouseDownWasSystemChrome = true
            return
        }
        mouseDownWasSystemChrome = false
        mouseDownLocation = point
        mouseDownCursor = currentCursorProvider()
        mouseDownWindow = windowAtPoint(point)
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
            if let window = self.mouseDownWindow, self.windowFrame(window.id) != window.frame { return }

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

            let policy = self.policyResolver(AppIdentity(app))
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
            let read = await retriever.retrieveResponse(
                for: appIdentity,
                policy: policy,
                cursor: cursor,
                allowCopyFallback: false,
                trigger: TriggerSource(raw: "mouseHold")
            )
            self.recordRead(.init(status: read.status, traceID: read.traceID))
            if read.status == .targetChanged || read.status == .cancelled || read.status == .policyBlocked { return }
            let isEditable = read.isEditable
            if let result = read.result {
                retrievedText = result.text
                selectionBounds = result.bounds
                selectionHTML = result.html
                selectionRTF = result.rtf
                selectionFlavors = result.flavors
            }

            let canPaste = await probeTask?.value
            guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: read.traceID)); return
            }

            // If no text was actively selected, only inherit clipboard content when the press is
            // actually over editable text, decided structurally (see `pressIsOverEditableText`).
            // Trusting the *focused* element instead let a hold on a window background / toolbar /
            // static text paste the clipboard just because a field elsewhere was focused, and the
            // earlier I-beam signal did the same over read-only web text — browsers show a beam
            // over selectable text whether or not it is editable.
            if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let isEditableContext = await isPressOverEditableText(point, app.processIdentifier)
                guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: read.traceID)); return
            }
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
                  retrievedText.utf8.count <= Constants.maxTextLength else {
                self.recordRead(.init(status: retrievedText.utf8.count > Constants.maxTextLength ? .tooLarge : read.status, traceID: read.traceID))
                return
            }

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
                flavors: selectionFlavors,
                selectionGeneration: self.selectionGeneration,
                isEditable: isEditable,
                pasteTargetAvailable: canPaste,
                traceID: read.traceID
            )
            guard !Task.isCancelled else { return }
            guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: read.traceID)); return
            }
            prewarmInlineActions(for: context)
            await InlineResultEvaluator.shared.awaitPrewarmed(timeout: 0.025)
            guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: read.traceID)); return
            }
            delivered = true
            latestSelection = (context, canPaste)
            self.recordRead(.init(context: context, canPaste: canPaste,
                status: isClipboardFallback ? .clipboardFallback : .selection, retrievalStatus: read.status, traceID: read.traceID))
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

    internal func handleMouseUp(
        app: NSRunningApplication,
        cursor: CGPoint,
        clickCount: Int
    ) {
        selectionSourceApp = app
        let pressCursor = mouseDownCursor
        mouseDownCursor = nil
        let gestureWindow = mouseDownWindow
        mouseDownWindow = nil
        if let gestureWindow, windowFrame(gestureWindow.id) != gestureWindow.frame {
            // Moving/resizing/closing a window is not a text-selection gesture, even if its
            // focused editor still exposes an old selection or an enabled Copy command.
            cancelPendingSelection()
            mouseDownLocation = nil
            mouseDownWasSystemChrome = false
            Log.selection.debug("monitor: skipped window move or resize")
            return
        }
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

        // A text drag can finish in whitespace with an arrow/custom cursor. Keep the press's
        // I-beam as weak context only for an actual drag; the retriever still requires an enabled
        // Copy menu and rejects object-selection roles when AX cannot provide selected text.
        let isDrag = downPoint.map { point in
            let dx = cursor.x - point.x
            let dy = cursor.y - point.y
            return (dx * dx + dy * dy) > Self.dragThresholdSquared
        } ?? false
        guard isDrag || clickCount >= 2 else {
            clearSelection()
            return
        }
        // Triple-click selects a paragraph; Chromium reports degenerate or offset bounds for
        // those ranges, so only words (double-click) and drags are checked for locality.
        let gesture: SelectionGestureLocality.Gesture? = if isDrag, let downPoint {
            .drag(from: downPoint, to: cursor)
        } else if clickCount == 2 {
            .multiClick(at: cursor)
        } else {
            nil
        }
        let releaseCursor = currentCursorProvider()
        let retrievalCursor: CursorClass = isDrag && pressCursor == .beam ? .beam : releaseCursor
        // A drag or multi-click is a selection *gesture*, not a selection. Without an I-beam at the
        // press or the release the pointer was never over text, so the copy tier must stay shut:
        // a synthetic ⌘C against an app with nothing selected makes it play the system alert sound
        // and flash its Edit menu (#210, #159, #109). AX reads are unaffected and still deliver a
        // selection the app exposes.
        let hasTextCue = pressCursor == .beam || releaseCursor == .beam
        Log.selection.debug("monitor: mouse selection context press=\(pressCursor?.rawValue ?? "none", privacy: .public) release=\(releaseCursor.rawValue, privacy: .public) retrieval=\(retrievalCursor.rawValue, privacy: .public) drag=\(isDrag, privacy: .public) textCue=\(hasTextCue, privacy: .public)")

        debounceTask = Task { @MainActor in
            guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged)); return
            }
            if let downPoint, await self.isPressOnWindowChrome(downPoint, app.processIdentifier) {
                guard self.isSelectionSourceActive(app) else { return }
                Log.selection.debug("monitor: skipped press on window chrome bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)")
                self.latestSelection = nil
                self.recordRead(.init(status: .copyBlocked))
                return
            }
            guard self.isSelectionSourceActive(app) else { return }
            // Native title-bar double-click zoom can update the window frame just after mouse-up.
            // Let AppKit settle that operation before treating a multi-click as a text gesture.
            if clickCount >= 2 {
                do {
                    try await Task.sleep(nanoseconds: self.multiClickWindowSettleNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, self.isSelectionSourceActive(app) else {
                    self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged)); return
                }
                if let gestureWindow, self.windowFrame(gestureWindow.id) != gestureWindow.frame {
                    self.recordRead(.init(status: .copyBlocked))
                    self.latestSelection = nil
                    return
                }
            }
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = self.policyResolver(AppIdentity(app))
            if policy.disabled {
                return
            }
            
            let appIdentity = AppIdentity(app)
            // Keep monitoring (so `latestSelection` stays warm for ⌥⌘C) but never post a synthetic
            // ⌘C when:
            // 1. "Appear Automatically" is disabled (passive background caching must stay non-invasive)
            // 2. The app has `hotkeyOnly` policy
            // 3. A foreign overlay owns the key window
            // 4. The gesture carried no text cue (see `hasTextCue` above) and the app does not
            //    declare copy as its only retrieval path. A copy-only policy means the AX tree
            //    cannot expose the selection, so refusing the copy removes the only read path;
            //    the copy engine still requires selection evidence and an enabled Copy command.
            let isAutoEnabled = self.settingsStore.get(.isAppEnabled)
            let isCopyOnlyPolicy = policy.retrievalMode == .keyboardCopy
            let allowCopyFallback = isAutoEnabled && !policy.hotkeyOnly
                && !self.isOverlayPresent(cursor) && (hasTextCue || isCopyOnlyPolicy)
            if isAutoEnabled, !policy.hotkeyOnly, !hasTextCue, !isCopyOnlyPolicy {
                Log.selection.debug("monitor: copy fallback withheld, no text cursor cue bundleID=\(app.bundleIdentifier ?? "unknown", privacy: .public)")
            }
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            let response = await retriever.retrieveResponse(
                for: appIdentity,
                policy: policy,
                cursor: retrievalCursor,
                allowCopyFallback: allowCopyFallback,
                trigger: clickCount >= 2 ? .doubleClick : .dragEnd
            )
            if Task.isCancelled { self.recordRead(.init(status: .cancelled, traceID: response.traceID)); return }
            await self.deliverSelection(
                response: response,
                app: app,
                appIdentity: appIdentity,
                policy: policy,
                cursor: cursor,
                mouseDownLocation: downPoint,
                gesture: gesture,
                probeTask: nil
            )
        }
    }
    
    /// Keyboard selection gesture: retrieve under the frontmost app resolved *after* the debounce
    /// (a ⌘A/⇧+arrow in one app followed by a switch during the debounce window must target the
    /// now-frontmost app). `isSelectAll` marks a whole-container gesture (⌘A / ⌘L), which retrieval
    /// refuses on a row/list container (row selection in Finder/Mail/table views).
    internal func handleSelectionTrigger(isSelectAll: Bool) {
        clearSelection()
        selectionSourceApp = frontmostAppProvider()
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
            self.selectionSourceApp = app
            guard self.isSelectionSourceActive(app) else {
                self.recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged)); return
            }

            if self.isExcludedBundle(app.bundleIdentifier) {
                return
            }
            
            let policy = self.policyResolver(AppIdentity(app))
            if policy.disabled {
                return
            }
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            // Match the mouse-up path: passive caching stays AX-only when automatic appearance
            // is disabled, this app is hotkey-only, or a foreign overlay owns the key window.
            let response = await retriever.retrieveResponse(
                for: appIdentity,
                policy: policy,
                cursor: self.currentCursorProvider(),
                isSelectAll: isSelectAll,
                allowCopyFallback: self.settingsStore.get(.isAppEnabled) && !policy.hotkeyOnly
                    && !self.isOverlayPresent(self.currentMouseLocation()),
                requireCopyEvidence: false,
                trigger: .keyboardShortcut
            )
            if Task.isCancelled { self.recordRead(.init(status: .cancelled, traceID: response.traceID)); return }
            let anchor = Self.keyboardAnchor(
                bounds: response.result?.bounds,
                isSelectAll: isSelectAll,
                mouseLocation: self.currentMouseLocation()
            )
            await self.deliverSelection(
                response: response,
                app: app,
                appIdentity: appIdentity,
                policy: policy,
                cursor: anchor,
                mouseDownLocation: nil,
                gesture: nil,
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
        response: TextReadResponse,
        app: NSRunningApplication,
        appIdentity: AppIdentity,
        policy: AppPolicyContext,
        cursor: CGPoint,
        mouseDownLocation: CGPoint?,
        gesture: SelectionGestureLocality.Gesture?,
        probeTask: Task<Bool?, Never>?
    ) async {
        guard isSelectionSourceActive(app) else {
            recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: response.traceID))
            return
        }
        guard let result = response.result else {
            recordRead(.init(status: response.status, traceID: response.traceID))
            latestSelection = nil
            return
        }
        guard TextSanitizer.isSubstantial(result.text), result.text.utf8.count <= Constants.maxTextLength else {
            recordRead(.init(status: result.text.utf8.count > Constants.maxTextLength ? .tooLarge : .noSelection, traceID: response.traceID))
            latestSelection = nil
            return
        }
        if let gesture, !SelectionGestureLocality.admits(axBounds: result.bounds, gesture: gesture, screens: gestureScreens()) {
            Log.selection.debug("[Trace#\(response.traceID ?? 0, privacy: .public)] monitor: selection outside gesture bounds=\(String(describing: result.bounds), privacy: .public) gesture=\(String(describing: gesture), privacy: .public)")
            recordRead(.init(status: .noSelection, traceID: response.traceID))
            latestSelection = nil
            return
        }
        let capturedContext = SelectionContext(
            text: result.text,
            sourceApp: appIdentity,
            cursorPosition: cursor,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: result.bounds,
            timestamp: now(),
            appPolicy: policy,
            html: result.html,
            rtf: result.rtf,
            flavors: result.flavors,
            selectionGeneration: selectionGeneration,
            isEditable: response.isEditable,
            pasteTargetAvailable: nil,
            traceID: response.traceID
        )
        // Mouse-up starts this only after the retrieval has produced valid text. Keyboard callers
        // may pass a probe started alongside retrieval; hold-to-popup keeps its separate flow.
        let pasteProbeTask = probeTask ?? preparePasteProbe?(app, policy)
        let canPaste = await pasteProbeTask?.value
        guard isSelectionSourceActive(app) else {
            recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: response.traceID)); return
        }
        let context = capturedContext.with(pasteTargetAvailable: canPaste)
        prewarmInlineActions(for: context)
        await InlineResultEvaluator.shared.awaitPrewarmed(timeout: 0.025)
        guard isSelectionSourceActive(app) else {
            recordRead(.init(status: Task.isCancelled ? .cancelled : .targetChanged, traceID: response.traceID)); return
        }
        latestSelection = (context, canPaste)
        recordRead(.init(context: context, canPaste: canPaste, status: .selection, traceID: response.traceID))
        // "Appear Automatically" (isAppEnabled) is the global form of the per-app `hotkeyOnly`
        // rule: it suppresses the passive auto-show for mouse-release and keyboard selections
        // while leaving the explicit hold gesture (delivered in `handleMouseDown`, which never
        // routes through here) and the ⌥⌘C hotkey independent. Monitoring still runs, so
        // `latestSelection` stays warm for the hotkey.
        if !policy.hotkeyOnly, self.settingsStore.get(.isAppEnabled) {
            self.onSelection?(context, canPaste)
        } else {
            Log.selection.debug("[Trace#\(response.traceID ?? 0, privacy: .public)] presentation blocked hotkeyOnly=\(policy.hotkeyOnly, privacy: .public) enabled=\(self.settingsStore.get(.isAppEnabled), privacy: .public)")
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
