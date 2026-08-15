// PopupWindowController.swift
// OpenClip
//
// Manages the window lifecycle, event tracking, positioning, and animation of the main floating popup panel.
// Owns the popup mode state machine (actions bar ↔ action-search palette ↔ native AI result card): search
// mode makes the panel key (a scoped exception to the never-key rule) and restores focus to the
// previous app on exit; content mode renders the AI result card inline on the panel and — since
// Task 14 — is also key, reusing the same enterKeyMode()/exitKeyMode() primitives as search, with
// Esc owned by the SwiftUI card (the controller-level key monitor stays observation-only in
// content mode).
// Implements the decision-8 ActionResult tree-walk (handleActionResult): presentation results render
// here, leaf effects route to DefaultActionResultHandler, and dismissal is decided once via
// ActionResult.dismissesPopup.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    private var currentActionContext: ActionContext?
    private var cardAbove = false
    /// Popup display mode (actions bar ↔ search palette ↔ AI result card), observed by PopupView.
    public let modeStore = PopupModeStore()
    /// Records action usage for search recency ranking.
    private let usageStore = ActionUsageStore()
    /// Frontmost app before the panel became key (search or content); captured once per session in
    /// show(for:), reactivated on exitKeyMode/hide, cleared only by hide(). Internal for tests.
    var previousFrontmostApp: NSRunningApplication?

    private var hoveredAction: (any Action)?

    private var isMenuTracking = false

    /// Tracks whether a right-click mouse-down originated within the popup bar.
    private var isRightClickInProgress = false

    /// How the most recent bar/palette action was triggered (left-click vs right/⇧-click). Set by
    /// the mouse monitor on mouse-down and reset by hide(). Snapshotted into a `DeliveryContext`
    /// when an action performs — never read as live state after an await. Drives the standardized
    /// paste-vs-copy delivery decision (`ActionResultDelivery`).
    private var pendingClickIntent: ActionResultDelivery.ClickIntent = .leftClick

    /// Probes whether the frontmost app supports Paste. Injected for tests.
    private let pasteProbe: PasteAvailabilityProbing

    /// The floating toast surface for statuses and the paste→copy "Copied" notice. Independent of
    /// the popup panel: it shows whether the popup is up or has already hidden. Injected for tests.
    private let toastController: ToastPanelController

    public init(resultHandler: ActionResultHandler = DefaultActionResultHandler(),
                pasteProbe: PasteAvailabilityProbing = PasteAvailabilityProbe(),
                toastController: ToastPanelController = ToastPanelController()) {
        self.resultHandler = resultHandler
        self.pasteProbe = pasteProbe
        self.toastController = toastController
    }

    /// Kicks off the paste-availability probe for the given target app (rules first, then the AX
    /// menu walk on its own queue). Trigger sites run this in parallel with selection retrieval,
    /// then hand the awaited result to `show(for:pasteAvailable:)` so the bar/search render Paste/
    /// Cut correctly on the first frame. Nothing is cached: paste availability tracks the target
    /// app's *focus context* (editable field vs read-only view), which can differ between shows in
    /// the same app — unless a per-app rule (assume/deny paste) answers definitively.
    public func preparePasteProbe(for app: NSRunningApplication?, policy: AppPolicyContext) -> Task<Bool?, Never> {
        Task { @MainActor in
            await pasteProbe.canPaste(in: app, policy: policy)
        }
    }

    public func show(for context: SelectionContext, pasteAvailable: Bool? = nil) {
        isMenuTracking = false
        currentContext = context

        // The source app is frontmost when the popup shows; capture it once for the whole session.
        // Skip the capture while OpenClip itself is frontmost (e.g. a preference window, or a mid-
        // session re-show): storing ourselves makes the later re-activation a no-op that loses the real
        // source app. Search re-entry and content↔search hops must never re-capture, either.
        captureFrontmostAppIfNeeded()

        let actionContext = ActionContext(selection: context, modifiers: [])
        currentActionContext = actionContext
        let availableActions = ActionCoordinator.shared.resolveActions(for: actionContext)

        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        // A fresh show is an intentional placement: never re-anchor it (stale search-mode pinning
        // must not correct the new frame). enterSearch() re-enables pinning for growth.
        panel.pinBottomEdgeOnResize = false
        panel.recenterXOnResize = false

        // Pre-compute card direction from real screen position
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let tempFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: CGSize(width: 320, height: 50), in: screenBounds)
        cardAbove = tempFrame.minY < screenBounds.minY + PopupMetrics.cardAboveThreshold

        modeStore.mode = .actions
        modeStore.searchResultsAbove = cardAbove
        // Probed before selection retrieval by the trigger sites and resolved before this frame,
        // so the bar/search gate Paste/Cut correctly on the first render. `nil` keeps them visible.
        modeStore.canPaste = pasteAvailable

        let rootView = PopupView(
            actions: availableActions,
            context: actionContext,
            initialAICardAboveBar: cardAbove,
            modeStore: modeStore,
            onEnterSearch: { [weak self] in self?.enterSearch() },
            onExitSearch: { [weak self] in self?.exitSearch() },
            onExitContent: { [weak self] in self?.exitContent() },
            onCardEffect: { [weak self] result in
                self?.performCardEffect(result)
            },
            onResult: { [weak self] result in
                self?.deliverResult(result)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onAIStateChange: { _, _ in },
            onAIResult: { [weak self] text, isError, title in
                self?.showAIContent(text: text, isError: isError, title: title)
            },
            onHoveredActionChanged: { [weak self] action in
                self?.updateHoveredAction(action)
            },
            onEnteredScopedSearch: { [weak self] action in
                self?.enterScopedSearch(for: action)
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            },
            onRunLoadingAction: { [weak self] action in
                guard let self, let context = self.currentActionContext else { return }
                self.runLoadingAction(action, with: context, forceCopy: self.pendingClickIntent == .forceCopy)
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .leftClick }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)

        // Compute card direction from real screen position using the actual rendered panel size.
        let calculatedFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: size, in: screenBounds)
        cardAbove = calculatedFrame.minY < screenBounds.minY + PopupMetrics.cardAboveThreshold
        modeStore.searchResultsAbove = cardAbove

        positionPanel(panel, size: size, for: context)
        // Placement is fixed; any subsequent content-driven width change (search palette,
        // pagination) must re-center rather than drift off the cursor.
        panel.recenterXOnResize = true
        // Content-driven growth keeps the panel's bottom edge fixed when the popup sits low on
        // screen — same anchor rule as search/content mode.
        panel.pinBottomEdgeOnResize = cardAbove
        panel.orderFront(nil)
        
        setupMonitors()
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    /// Hotkey-driven mode toggle: actions → search palette → dismiss.
    public func toggleMode() {
        guard panel?.isVisible == true else { return }
        switch modeStore.mode {
        case .actions:
            enterSearch()
        case .search:
            hide()
        case .content:
            exitContent()
        }
    }

    /// Records the app that was frontmost before the panel made itself key (search, or later the
    /// AI result card). Captures only when no session value exists yet — mid-session re-entry must
    /// keep the original source app — and only when that app is not OpenClip itself. Used by show(for:)
    /// (session start) and enterKeyMode() (direct key entry); hide() is the only thing that clears it.
    private func captureFrontmostAppIfNeeded() {
        guard previousFrontmostApp == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousFrontmostApp = app
    }

    /// Makes the panel key (a scoped, user-initiated exception to the never-key rule) so a key
    /// component can receive typing. A nonactivating panel can become key without activating this
    /// app, so the source app stays active throughout. Captures the frontmost app only when no
    /// session value exists yet — mid-session re-entry (search → bar → search, or content → search)
    /// must keep the original source app — and only when that app is not OpenClip itself.
    private func enterKeyMode() {
        guard let panel, panel.isVisible else { return }
        captureFrontmostAppIfNeeded()
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
    }

    /// Restores the never-key invariant and hands keyboard focus back to the source app. Deliberately
    /// does NOT clear previousFrontmostApp: only hide() ends the session, so the same source app is
    /// re-activated on the next exit and re-used on the next enter.
    private func exitKeyMode() {
        panel?.allowsKey = false
        if NSApp.isActive {
            previousFrontmostApp?.activate(options: [.activateAllWindows])
        }
    }

    /// Enter search mode, optionally scoped to a parent action's sub-actions: the panel becomes key
    /// (a scoped, user-initiated exception to the never-key rule) so the search field can receive
    /// typing. A nonactivating panel can become key without activating this app, so the source app
    /// stays active throughout.
    public func enterSearch(with scope: SearchScope? = nil) {
        guard panel?.isVisible == true else { return }
        if modeStore.mode != .search || scope != nil {
            modeStore.scope = scope
        }
        modeStore.mode = .search
        // Content-driven growth keeps the panel's bottom edge fixed (results render above the field,
        // so growth must extend upward); see PopupPanel.setFrame.
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        enterKeyMode()
        // Explicitly make the search field first responder on the next run-loop turn. A @FocusState
        // request issued during the mode-change render can be silently dropped on macOS before the
        // panel has finished becoming key (worst on the click-path: the click that opened search).
        Task { @MainActor in
            await Task.yield()
            self.focusSearchField()
        }
    }

    /// Opens the palette scoped to a bar row's sub-actions. The parent action supplies its children
    /// via `SubActionProviding` (core, id/`.ai`-driven); resolution happens here so the view never
    /// type-checks against the action catalog.
    private func enterScopedSearch(for action: any Action) {
        guard let actionContext = currentActionContext else { return }
        let children = SubActionResolver().subActions(
            of: action,
            in: ActionCoordinator.shared.searchCatalog(for: actionContext)
        )
        enterSearch(with: SearchScope(parent: action, children: children))
    }

    private func focusSearchField() {
        guard let panel, panel.isVisible, modeStore.mode == .search else { return }
        guard let field = findTextInput(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    private func findTextInput(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSTextView || view is NSTextField { return view }
        for subview in view.subviews {
            if let found = findTextInput(in: subview) { return found }
        }
        return nil
    }

    /// Leave search mode back to the actions bar: restore the never-key invariant and hand
    /// keyboard focus back to the source app. Never hides the popup. The bottom-edge pin is kept
    /// active through the shrink so the bar returns to the field's spot (results-above case);
    /// it is cleared by hide() and the next show(for:).
    public func exitSearch() {
        guard modeStore.mode == .search else { return }
        modeStore.scope = nil
        modeStore.mode = .actions
        // Return to the bar keeps the field-anchoring rule active for hover-preview/banner growth
        // (strip renders above the bar when the popup sits low), so set it explicitly rather than
        // leaving the search-mode value behind. Cleared by show()/hide() before placement.
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        exitKeyMode() // reactivates previousFrontmostApp but keeps it for the session
    }

    // MARK: - AI Result Card

    /// Shows the AI provider's response (or error) in the native result card, entering content
    /// mode and making the panel key so Esc can collapse the card. Paste/Copy are explicit
    /// user requests routed through `performCardEffect`, so they bypass the paste-vs-copy
    /// re-decision — an explicit Paste always pastes. Probes (AX) whether the target app can paste
    /// so the card can hide its Paste button; the probe targets the captured source app, never
    /// OpenClip itself. Internal for tests.
    func showAIContent(text: String, isError: Bool, title: String) {
        modeStore.aiResult = AIResultPayload(text: text, isError: isError, title: title)
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        panel?.recenterXOnResize = true
        modeStore.mode = .content
        enterKeyMode()
    }

    /// Collapses the AI result card back to the actions bar. Never hides the popup.
    public func exitContent() {
        guard modeStore.mode == .content else { return }
        modeStore.aiResult = nil
        modeStore.mode = .actions
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        exitKeyMode()
    }

    // MARK: - Hovered Action

    /// Tracks the hovered bar row so the right-click path can run it directly. Re-entry with the
    /// same action id is a no-op.
    private func updateHoveredAction(_ action: (any Action)?) {
        guard action?.id != hoveredAction?.id else { return }
        hoveredAction = action
    }

    /// Runs an explicit card button (Paste/Copy) — an explicit user request, so it carries no
    /// delivery context and bypasses the paste-vs-copy re-decision. Dismissing results hide the
    /// popup first (so exitKeyMode() reactivates the target app) before handling.
    private func performCardEffect(_ result: ActionResult) {
        if result.dismissesPopup {
            hide()
            handleActionResult(result, delivery: nil)
        } else {
            _ = handleEffect(result, delivery: nil)
        }
    }

    // MARK: - Panel Resize

    /// Resize the bar/search panel, keeping the field's edge fixed so entering search mode never
    /// jumps the popup. With results below the field the field is at the palette top (anchor the top
    /// edge, grow down); with results above the field the field is at the palette bottom (anchor the
    /// bottom edge, grow up). Horizontal re-centering and screen/height clamping are handled by
    /// `PopupPanel.setFrame`, which is the single funnel the hosting view's auto-resize also uses.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        let size = sanitizedPopupSize(proposedSize)
        let current = panel.frame.size
        if abs(current.width - size.width) < 1, abs(current.height - size.height) < 1 { return }
        if modeStore.searchResultsAbove {
            // Field at the palette bottom: keep the bottom edge fixed, grow upward.
            panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.minY,
                                  width: size.width, height: size.height), display: true)
        } else {
            // Field at the palette top: keep the top edge fixed, grow downward.
            let newOriginY = panel.frame.maxY - size.height
            panel.setFrame(CGRect(x: panel.frame.minX, y: newOriginY,
                                  width: size.width, height: size.height), display: true)
        }
    }

    private func sanitizedPopupSize(_ raw: CGSize?) -> CGSize {
        var size = raw ?? CGSize(width: 300, height: 54)
        size.width = max(size.width, 100)
        size.height = max(size.height, 30)
        return size
    }

    private func positionPanel(_ panel: PopupPanel, size: CGSize, for context: SelectionContext) {
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: size,
            in: screenBounds
        )
        panel.setFrame(frame, display: true)
    }

    public func hide() {
        modeStore.aiResult = nil
        modeStore.canPaste = nil
        // A dismissed session must not leak its click intent into the next one (keyboard-driven
        // runs and any later snapshot read the last intent; force-copy must never persist).
        pendingClickIntent = .leftClick
        isRightClickInProgress = false
        modeStore.mode = .actions
        modeStore.scope = nil
        panel?.pinBottomEdgeOnResize = false
        panel?.recenterXOnResize = false
        exitKeyMode() // allowsKey=false + reactivate previousFrontmostApp
        previousFrontmostApp = nil // hide() is the only thing that ends the key-mode session
        panel?.orderOut(nil)
        removeMonitors()
        currentContext = nil
        currentActionContext = nil
        hoveredAction = nil
        isMenuTracking = false
        PopupHoverState.shared.location = nil
    }
    
    private func setupMonitors() {
        removeMonitors()

        let canMonitorGlobally = PermissionManager.shared.isAccessibilityGranted
        PopupHoverState.shared.usesGlobalMouseMonitoring = canMonitorGlobally
        if canMonitorGlobally {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .rightMouseUp, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
            }
        } else {
            Log.presentation.notice("Accessibility permission unavailable; using local hover tracking.")
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    @objc private func menuDidBeginTracking() {
        isMenuTracking = true
    }
    
    @objc private func menuDidEndTracking() {
        isMenuTracking = false
    }
    
    private func removeMonitors() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }
        
        switch event.type {
        case .mouseMoved:
            updatePopupHover(at: NSEvent.mouseLocation)
            let cursorLoc = NSEvent.mouseLocation
            // Distance dismissal suspends in search mode (typing elsewhere must not dismiss the
            // palette) and while the AI result card is open (modal); it is active otherwise.
            let distanceDismissActive = modeStore.mode != .search && modeStore.mode != .content
            if distanceDismissActive, let panel = panel {
                let frame = panel.frame
                let dx = max(0, max(frame.minX - cursorLoc.x, cursorLoc.x - frame.maxX))
                let dy = max(0, max(frame.minY - cursorLoc.y, cursorLoc.y - frame.maxY))
                if hypot(dx, dy) > PopupMetrics.popupDismissalDistance {
                    hide()
                }
            }
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            let inBar = panel?.frame.contains(clickLoc) ?? false
            // Capture the modifier state at click time so the action that runs on mouse-up (via the
            // SwiftUI Button) delivers as a copy when ⇧ is held.
            let isShift = event.modifierFlags.contains(.shift)
            pendingClickIntent = isShift ? .forceCopy : .leftClick
            if !inBar {
                hide()
            }
        case .rightMouseDown:
            // Right-click down: prepare force-copy intent and mark right-click in progress.
            // Execution waits for rightMouseUp (matching standard button click-release semantics).
            let clickLoc = NSEvent.mouseLocation
            let inBar = panel?.frame.contains(clickLoc) ?? false
            if inBar {
                pendingClickIntent = .forceCopy
                isRightClickInProgress = true
            } else {
                isRightClickInProgress = false
                hide()
            }
        case .rightMouseUp:
            guard isRightClickInProgress else { break }
            isRightClickInProgress = false
            let clickLoc = NSEvent.mouseLocation
            let inBar = panel?.frame.contains(clickLoc) ?? false
            if inBar, let hoveredAction, let actionContext = currentActionContext, modeStore.mode == .actions {
                runAction(hoveredAction, with: actionContext, forceCopy: true)
            }
        case .scrollWheel:
            // Search mode scrolls the results list (panel key); the AI result card is modal and
            // scrolls its own content, never dismisses.
            if modeStore.mode == .search || modeStore.mode == .content { break }
            // A 2-finger tap (trackpad right-click) generates a phantom scrollWheel with
            // .mayBegin/.cancelled phase and zero deltas before rightMouseDown arrives. Ignore
            // these so the right-click gesture is not killed by the scroll dismissal.
            let dominated = event.phase == .mayBegin || event.phase == .cancelled
            let zeroScroll = event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0
            if dominated && zeroScroll { break }
            hide()
        case .keyDown:
            // Actions mode: any keystroke (including Escape) dismisses the popup; the panel is
            // never key here, so keys land in the source app and are merely observed.
            // Search mode: keys go to the search field (panel is key); Escape is handled there.
            // Content mode: the card is key (Task 14) — Esc belongs to the SwiftUI card
            // (.onKeyPress(.escape) calls onExitContent()), so the monitor stays observation-only
            // here. Handling Esc a second time at the controller would double-fire on top of
            // SwiftUI (M8).
            if modeStore.mode == .search { break }
            if modeStore.mode == .content {
                return   // Esc belongs to the card component (SwiftUI .onKeyPress);
                         // the global monitor stays observation-only — do NOT handle Esc here (M8)
            }
            hide()
        default:
            break
        }
    }

    private func updatePopupHover(at screenLocation: CGPoint) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else {
            PopupHoverState.shared.location = nil
            return
        }

        let windowPoint = panel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard contentView.bounds.contains(contentPoint) else {
            PopupHoverState.shared.location = nil
            return
        }

        let y = contentView.isFlipped ? contentPoint.y : contentView.bounds.height - contentPoint.y
        let point = CGPoint(x: contentPoint.x, y: y)
        // The global monitor fires on every mouse move even when the pointer hasn't crossed a new
        // pixel boundary; `@Published` emits on every assignment, so skip identical locations to
        // keep the `.onReceive` hit-tests from re-running at event-monitor rate.
        guard point != PopupHoverState.shared.location else { return }
        NSCursor.arrow.set()
        PopupHoverState.shared.location = point
    }
    
    @objc private func appDidDeactivate() {
        // A right-click fires didResignActiveNotification before rightMouseUp arrives; suppressing
        // hide() here lets the right-click path complete on mouse-up as intended.
        if !isMenuTracking && !isRightClickInProgress {
            hide()
        }
    }
    
    /// Settable in `init` so the effect-delivery tests can inject a recording handler.
    var resultHandler: ActionResultHandler

    // MARK: - Decision 8: ActionResult Tree-Walk

    /// The inputs to the paste-vs-copy delivery decision, captured synchronously when an action
    /// performs — before `hide()` can clear the live context, and before any async probe await.
    /// `nil` (an explicit user request, e.g. the AI card's Paste/Copy buttons) means the result is never re-decided.
    struct DeliveryContext {
        let policy: AppPolicyContext
        let clickIntent: ActionResultDelivery.ClickIntent
        /// The target app the result will be delivered to. Captured synchronously with the other
        /// inputs: while the (non-activating) panel is up, the source app stays frontmost, and
        /// `exitKeyMode()` reactivates exactly this app on hide — so the snapshot is the same app
        /// `pasteProbe` must inspect, without reading frontmost state after hide or an await.
        let application: NSRunningApplication?
    }

    /// Snapshots the delivery inputs from the current session state. Called on the main actor,
    /// synchronously, before any dismissal or await, so the decision never depends on live state
    /// read after `hide()` or after the probe suspension.
    private func deliverySnapshot() -> DeliveryContext {
        DeliveryContext(
            policy: currentActionContext?.selection.appPolicy ?? .default,
            clickIntent: pendingClickIntent,
            application: NSWorkspace.shared.frontmostApplication
        )
    }

    /// Routes a performed result into the tree-walk, snapshotting the delivery inputs first.
    /// Decision 8: dismissal is decided once on the top-level result; the tree-walk never hides
    /// per-item. `hide()` runs before `handleActionResult` so `exitKeyMode()` reactivates the target
    /// source app before any synthetic keyboard events (.paste, .cut, etc.) are posted — and the
    /// delivery snapshot is taken before that `hide()` clears the live context. Internal for tests.
    func deliverResult(_ result: ActionResult) {
        let delivery = deliverySnapshot()
        if result.dismissesPopup {
            hide()
        }
        handleActionResult(result, delivery: delivery)
    }

    /// Walks an ActionResult produced by a perform, rendering presentation results in the popup and
    /// routing leaf effects to the effect handler. Never hides the popup per-item — dismissal is
    /// decided once on the top-level result via `dismissesPopup`. `delivery` carries the captured
    /// paste-vs-copy inputs; `nil` means the result is an explicit user request never re-decided.
    func handleActionResult(_ result: ActionResult, delivery: DeliveryContext? = nil) {
        switch result {
        case .showStatus(let feedback):
            presentStatus(feedback)
        case .openConfiguration(let request):
            presentConfiguration(for: request)
        case .sequence(let items):
            for item in items { handleActionResult(item, delivery: delivery) }
        default:
            handleEffect(result, delivery: delivery)
        }
    }

    /// Routes a leaf effect to DefaultActionResultHandler and surfaces any thrown error uniformly
    /// (decision 9): an error becomes a `.showStatus(.error)` and the popup stays. Returns the task
    /// so a caller can await the posted effect.
    ///
    /// Applies the standardized paste-vs-copy delivery decision (`.paste` → `.copy` when the click
    /// was a force-copy, the app policy forbids paste, or the target app can't Paste). Only leaf
    /// text results routed here are re-decided; explicit user requests (the AI card's Paste/Copy
    /// buttons) pass through untouched via a nil `delivery`.
    @discardableResult
    private func handleEffect(_ result: ActionResult, delivery: DeliveryContext?) -> Task<Void, Never> {
        let effect = result
        return Task { @MainActor in
            do {
                let delivered = await resolveDelivery(effect, delivery: delivery)
                try await resultHandler.handle(delivered, in: panel?.contentView)
                let isDowngradedToCopy = if case .paste = effect, case .copy = delivered { true } else { false }
                let isCopyDefinition = if case .copyDefinition = delivered { true } else { false }
                if isDowngradedToCopy || isCopyDefinition {
                    toastController.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"), anchorFrame: panel?.frame)
                }
            } catch {
                handleActionResult(.showStatus(StatusFeedback(error: error)))
            }
        }
    }

    /// Decides how a text result should be delivered, per the standardized rule. Only `.paste`
    /// outcomes can be downgraded to `.copy`; everything else — and any result without a captured
    /// `delivery` (an explicit user request) — passes through untouched. The click intent and app
    /// policy come from the snapshot, never from live state read after an await.
    private func resolveDelivery(_ result: ActionResult, delivery: DeliveryContext?) async -> ActionResult {
        guard case .paste = result, let delivery else { return result }
        // The unified paste decision: per-app rules (assume/deny paste) answer definitively and
        // skip the AX walk entirely (no Accessibility dependency for those apps); a force-copy click
        // also skips it (the outcome is a copy regardless). Otherwise probe the target app and treat
        // unknown availability as cannot-paste — the safe default: never paste blindly when we
        // cannot confirm the target supports it. The target is the snapshotted app captured before
        // hide(), never frontmost state read after suspension.
        let canPaste: Bool
        if delivery.clickIntent == .forceCopy || !PasteAvailability.needsProbe(policy: delivery.policy) {
            canPaste = PasteAvailability.effective(policy: delivery.policy, probe: nil) ?? false
        } else {
            canPaste = await pasteProbe.canPaste(in: delivery.application, policy: delivery.policy) ?? false
        }
        return ActionResultDelivery.resolve(
            raw: result,
            clickIntent: delivery.clickIntent,
            canPaste: canPaste
        )
    }

    /// Performs an action directly (the right-click path, which the bar's SwiftUI Button never
    /// fires) and routes its result through the standard dismissal + tree-walk, recording usage.
    /// Mirrors the left-click perform path in PopupView. The delivery context is built here from
    /// `forceCopy`, so the decision never depends on live state read after the perform await.
    /// Internal for tests (mirrors `runLoadingAction`).
    func runAction(_ action: any Action, with context: ActionContext, forceCopy: Bool) {
        if action.chrome.showsLoading {
            runLoadingAction(action, with: context, forceCopy: forceCopy)
            return
        }
        let clickIntent: ActionResultDelivery.ClickIntent = forceCopy ? .forceCopy : .leftClick
        pendingClickIntent = clickIntent
        // Snapshot the target app with the rest of the delivery inputs, before the perform await
        // and before hide() can reactivate a different frontmost app.
        let delivery = DeliveryContext(
            policy: context.selection.appPolicy,
            clickIntent: clickIntent,
            application: NSWorkspace.shared.frontmostApplication
        )
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            forceCopy: forceCopy,
            match: match
        )
        Task { @MainActor in
            do {
                let result = try await action.perform(performContext)
                if result.dismissesPopup {
                    self.hide()
                }
                self.handleActionResult(result, delivery: delivery)
            } catch {
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                self.handleActionResult(.showStatus(StatusFeedback(error: error)))
            }
        }
    }

    /// Performs a `showsLoading` action with early-close: the popup hides immediately, a spinner
    /// toast appears at the cursor, and the result settles the toast (swap to description, or fade
    /// when the result carries none). Mirrors runAction's delivery snapshot: captured before the
    /// early hide so paste-vs-copy still sees the pre-dismissal context. Internal for tests.
    func runLoadingAction(_ action: any Action, with context: ActionContext, forceCopy: Bool) {
        let clickIntent: ActionResultDelivery.ClickIntent = forceCopy ? .forceCopy : .leftClick
        pendingClickIntent = clickIntent
        let delivery = DeliveryContext(
            policy: context.selection.appPolicy,
            clickIntent: clickIntent,
            application: NSWorkspace.shared.frontmostApplication
        )
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            forceCopy: forceCopy,
            match: match
        )
        let anchorFrame = panel?.frame
        hide()
        let message = action.chrome.loadingMessage ?? "Opening \(action.title)…"
        toastController.showLoading(message: message, anchorFrame: anchorFrame)
        Task { @MainActor in
            do {
                let result = try await action.perform(performContext)
                await settleLoadingResult(result, delivery: delivery)
            } catch {
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                await settleLoadingResult(.showStatus(StatusFeedback(error: error)), delivery: delivery)
            }
        }
    }

    /// Resolves a loading action's result into the toast: `.showStatus` swaps to that status,
    /// a paste→copy downgrade swaps to "Copied", a leaf with an effect that delivers swaps to
    /// "Copied" on downgrade, and everything else (`.success`, `.openURL`, honored paste, native
    /// copy) fades the spinner.
    private func settleLoadingResult(_ result: ActionResult, delivery: DeliveryContext) async {
        switch result {
        case .showStatus(let feedback):
            toastController.show(feedback)
        case .openConfiguration(let request):
            toastController.hide()
            presentConfiguration(for: request)
        case .sequence(let items):
            for item in items { await settleLoadingResult(item, delivery: delivery) }
        default:
            let effect = result
            do {
                let delivered = await resolveDelivery(effect, delivery: delivery)
                if case .paste = effect, case .copy = delivered {
                    try await resultHandler.handle(delivered, in: panel?.contentView)
                    toastController.swapTo(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
                } else {
                    try await resultHandler.handle(delivered, in: panel?.contentView)
                    toastController.hide()
                }
            } catch {
                await settleLoadingResult(.showStatus(StatusFeedback(error: error)), delivery: delivery)
            }
        }
    }

    /// Surfaces a StatusFeedback as the floating toast (the single status renderer). The toast
    /// is independent of the popup, so it shows whether the popup stays up or has already hidden.
    private func presentStatus(_ feedback: StatusFeedback) {
        toastController.show(feedback, anchorFrame: panel?.frame)
    }

    /// Decision 8 config-open path: the popup has already hidden (`.openConfiguration` dismisses it);
    /// post the configuration notification so the Preferences host presents the action's
    /// EditActionSheet (StatusBarController opens Preferences and drives the sheet).
    private func presentConfiguration(for request: ConfigurationRequest) {
        NotificationCenter.default.post(
            name: .openClipOpenActionConfiguration,
            object: nil,
            userInfo: ["request": request]
        )
    }
}
