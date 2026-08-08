// PopupWindowController.swift
// OpenClip
//
// Manages the window lifecycle, event tracking, positioning, and animation of the main floating popup panel.
// Owns the popup mode state machine (actions bar ↔ action-search palette ↔ content canvas): search
// mode makes the panel key (a scoped exception to the never-key rule) and restores focus to the
// previous app on exit; content mode renders action/AI results inline on the panel, stays non-key
// today (the content canvas blocks distance/scroll dismissal and non-Esc keys), and the interactive
// canvas (Task 14) will make the panel key and reuse enterKeyMode()/exitKeyMode(), which are also
// the search-mode path. Also owns the hover-debounce
// and long-press timers that feed the preview strip / result canvas per Action.gesturePolicy.
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
    /// Popup display mode (actions bar ↔ search palette), observed by PopupView.
    public let modeStore = PopupModeStore()
    /// Records action usage for search recency ranking.
    private let usageStore = ActionUsageStore()
    /// Frontmost app before the panel became key (search or, later, canvas); captured once per
    /// session in show(for:), reactivated on exitKeyMode/hide, cleared only by hide(). Internal
    /// for tests.
    var previousFrontmostApp: NSRunningApplication?

    private var hoverDebounceTask: Task<Void, Never>?
    private var longPressTask: Task<Void, Never>?
    private var hoveredAction: (any Action)?
    private var longPressFired = false
    /// Top-trailing status badge shown on the open content canvas (decision 10). Backed by the shared
    /// StatusBadgeModel so an already-mounted PopupContentView re-renders when a status arrives.
    private var currentStatusBadge: StatusFeedback? {
        get { StatusBadgeModel.shared.currentStatusBadge }
        set { StatusBadgeModel.shared.currentStatusBadge = newValue }
    }
    /// Auto-dismiss timer for the non-blocking status info bubble.
    private var statusDismissTask: Task<Void, Never>?
    /// How long the non-blocking status info bubble stays up before auto-dismissing.
    private let statusBubbleDurationNanoseconds: UInt64 = 1_500_000_000

    private var isMenuTracking = false
    
    public init() { }
    
    public func show(for context: SelectionContext) {
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
            for: context, popupSize: CGSize(width: 320, height: 54), in: screenBounds)
        cardAbove = tempFrame.minY < screenBounds.minY + 280

        modeStore.mode = .actions
        modeStore.searchResultsAbove = cardAbove

        let rootView = PopupView(
            actions: availableActions,
            context: actionContext,
            initialAICardAboveBar: cardAbove,
            modeStore: modeStore,
            onEnterSearch: { [weak self] in self?.enterSearch() },
            onExitSearch: { [weak self] in self?.exitSearch() },
            onExitContent: { [weak self] in self?.exitContent() },
            onContentOutcome: { [weak self] outcome in
                guard let self, case .perform(let inner) = outcome else { return }
                if case .paste = inner {
                    self.handleActionResult(inner)
                    self.hide()
                } else {
                    self.exitContent()
                    self.handleActionResult(inner)
                }
            },
            onResult: { [weak self] result in
                guard let self else { return }
                // Decision 8: dismissal is decided once on the top-level result; the tree-walk never
                // hides per-item.
                if result.dismissesPopup {
                    self.hide()
                }
                self.handleActionResult(result)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
                        onAIStateChange: { _, _ in },
            onAIResult: { [weak self] text, isError in
                self?.showAIContent(text: text, isError: isError)
            },
            onHoveredActionChanged: { [weak self] action in
                self?.updateHoveredAction(action)
            },
            onEnteredScopedSearch: { [weak self] action in
                self?.enterScopedSearch(for: action)
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)
        positionPanel(panel, size: size, for: context)
        // Placement is fixed; any subsequent content-driven width change (search palette,
        // pagination) must re-center rather than drift off the cursor.
        panel.recenterXOnResize = true
        // The hover preview strip renders above the bar when the popup sits low on screen, so its
        // growth must pin the bottom edge too — same anchor rule as search/content mode.
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
            // Not reachable until Task 3 wires the canvas; hotkey collapses back to the bar.
            modeStore.content = nil
            modeStore.mode = .actions
        }
    }

    /// Records the app that was frontmost before the panel made itself key (search, or later the
    /// interactive canvas). Captures only when no session value exists yet — mid-session re-entry must
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
        modeStore.scope = scope
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
        let children = SubActionResolver().subActions(
            of: action,
            in: ActionCoordinator.shared.searchCatalog
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

    // MARK: - Content Canvas

    /// Opens the content canvas for a result: the panel transforms into the canvas (bar hidden,
    /// like search mode). The panel stays non-key — Esc is observed by the event monitors.
    private func enterContent(_ content: PopupContent) {
        guard panel?.isVisible == true else { return }
        modeStore.content = content
        modeStore.mode = .content
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
    }

    /// Collapses the content canvas back to the actions bar. Never hides the popup.
    public func exitContent() {
        guard modeStore.mode == .content else { return }
        modeStore.content = nil
        modeStore.mode = .actions
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
    }

    /// Renders the AI response (or error) as a content canvas with Replace/Copy delivery options.
    private func showAIContent(text: String, isError: Bool) {
        let content = PopupContent(
            title: isError ? "AI Error" : "AI Result",
            icon: isError ? "exclamationmark.triangle" : "sparkles",
            rows: [.text(text)],
            footer: isError ? [] : [
                ContentOption(
                    title: "Replace",
                    icon: "arrow.triangle.2.circlepath",
                    outcome: .perform(.paste(text))
                ),
                ContentOption(
                    title: "Copy",
                    icon: "doc.on.doc",
                    outcome: .perform(.copy(text))
                )
            ],
            emphasis: .result
        )
        enterContent(content)
    }

    // MARK: - Hover Preview

    private func updateHoveredAction(_ action: (any Action)?) {
        // Re-entry with the same action id must not cancel a pending hover preview for it.
        guard action?.id != hoveredAction?.id else { return }
        hoverDebounceTask?.cancel()
        hoveredAction = action

        guard let action, let actionContext = currentActionContext, modeStore.mode == .actions else {
            modeStore.preview = nil
            return
        }

        guard action.gesturePolicy.hoverPreview else {
            modeStore.preview = nil
            return
        }

        hoverDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.bubbleHoverDelayNanoseconds)
            guard !Task.isCancelled,
                  self.hoveredAction?.id == action.id,
                  self.modeStore.mode == .actions else { return }

            let icon: String? = {
                if case .symbol(let name) = action.displayIcon(using: ActionCustomizationManager.shared) { return name }
                return nil
            }()
            let line = await (action as? any PreviewProviding)?.previewLine(for: actionContext)

            self.modeStore.preview = PopupContent(
                title: action.displayTitle(using: ActionCustomizationManager.shared),
                icon: icon,
                subtitle: line ?? action.displayTitle(using: ActionCustomizationManager.shared),
                emphasis: .info
            )
        }
    }

    // MARK: - Long-Press Canvas

    private func beginLongPressIfNeeded(at clickLocation: CGPoint) {
        longPressTask?.cancel()
        longPressFired = false

        guard let hoveredAction, hoveredAction.gesturePolicy.longPress != nil,
              let actionContext = currentActionContext,
              let panel, panel.frame.contains(clickLocation) else { return }

        let targetAction = hoveredAction
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.bubbleLongPressNanoseconds)
            guard !Task.isCancelled, self.hoveredAction?.id == targetAction.id else { return }
            guard let content = await (targetAction as? any ResultContentProviding)?.makeContent(for: actionContext) else {
                return
            }
            guard !Task.isCancelled else { return }
            longPressFired = true
            self.enterContent(content)
        }
    }
    
    // MARK: - Panel Resize

    /// Resize the bar/search panel, keeping the field's edge fixed so entering search mode never
    /// jumps the popup. With results below the field the field is at the palette top (anchor the top
    /// edge, grow down); with results above the field the field is at the palette bottom (anchor the
    /// bottom edge, grow up). Horizontal re-centering is handled by PopupPanel.setFrame
    /// (`recenterXOnResize`), which is the single funnel the hosting view's auto-resize also uses.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        var size = sanitizedPopupSize(proposedSize)
        let screenBounds = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let maxWidth = max(0, screenBounds.width - Constants.popupPadding * 2)
        size.width = min(size.width, maxWidth)
        // Cap the search palette height so a long result list scrolls instead of stretching off-screen.
        size.height = min(size.height, Constants.popupMaxHeight)
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
        statusDismissTask?.cancel()
        statusDismissTask = nil
        currentStatusBadge = nil
        modeStore.statusBanner = nil
        modeStore.content = nil
        modeStore.preview = nil
        hoverDebounceTask?.cancel()
        longPressTask?.cancel()
        longPressTask = nil
        longPressFired = false
        modeStore.mode = .actions
        modeStore.scope = nil
        panel?.pinBottomEdgeOnResize = false
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
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
            }
        } else {
            Log.presentation.notice("Accessibility permission unavailable; using local hover tracking.")
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
            if let self, event.type == .leftMouseUp {
                // A mouse-up always ends a pending long press: cancel the task so a quick click
                // doesn't later fire a result bubble, and swallow the trailing mouse-up only when
                // a long-press bubble was actually shown (so it doesn't also perform the action).
                self.longPressTask?.cancel()
                self.longPressTask = nil
                if self.longPressFired {
                    self.longPressFired = false
                    return nil
                }
            }
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
            // palette) and while a content canvas is open (modal); it is active otherwise.
            let distanceDismissActive = modeStore.mode != .search && modeStore.mode != .content
            if distanceDismissActive, let panel = panel {
                let frame = panel.frame
                let dx = max(0, max(frame.minX - cursorLoc.x, cursorLoc.x - frame.maxX))
                let dy = max(0, max(frame.minY - cursorLoc.y, cursorLoc.y - frame.maxY))
                if hypot(dx, dy) > Constants.popupDismissalDistance {
                    hide()
                }
            }
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            let inBar = panel?.frame.contains(clickLoc) ?? false
            if inBar {
                beginLongPressIfNeeded(at: clickLoc)
            }
            if !inBar {
                hide()
            }
        case .scrollWheel:
            // Search mode scrolls the results list (panel key); a content canvas is modal and
            // scrolls its own scrollable content, never dismisses.
            if modeStore.mode == .search || modeStore.mode == .content { break }
            hide()
        case .keyDown:
            // Actions mode: any keystroke (including Escape) dismisses the popup; the panel is
            // never key here, so keys land in the source app and are merely observed.
            // Search mode: keys go to the search field (panel is key); Escape is handled there.
            // Content mode: modal — Escape collapses the canvas to the bar; any other key is
            // ignored (it belongs to the focused canvas component, or pre-Task-14 to the source
            // app) and never dismisses.
            if modeStore.mode == .search { break }
            if modeStore.mode == .content {
                if event.keyCode == 53 { // Esc
                    exitContent()
                }
                return
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
        if !isMenuTracking {
            hide()
        }
    }
    
    private let resultHandler: ActionResultHandler = DefaultActionResultHandler()

    // MARK: - Decision 8: ActionResult Tree-Walk

    /// Walks an ActionResult produced by a perform, rendering presentation results in the popup and
    /// routing leaf effects to the effect handler. Never hides the popup per-item — dismissal is
    /// decided once on the top-level result via `dismissesPopup`.
    func handleActionResult(_ result: ActionResult) {
        switch result {
        case .showContent(let content):
            enterContent(content)
        case .showStatus(let feedback):
            presentStatus(feedback)
        case .openConfiguration(let request):
            presentConfiguration(for: request)
        case .keepVisible(let inner):
            handleActionResult(inner)
        case .sequence(let items):
            for item in items { handleActionResult(item) }
        default:
            handleEffect(result)
        }
    }

    /// Routes a leaf effect to DefaultActionResultHandler and surfaces any thrown error uniformly
    /// (decision 9): an error becomes a `.showStatus(.error)` and the popup stays.
    private func handleEffect(_ result: ActionResult) {
        guard let effect = result.effectForHandler else { return }
        Task { @MainActor in
            do {
                try await resultHandler.handle(effect, in: panel?.contentView)
            } catch {
                handleActionResult(.showStatus(StatusFeedback(error: error)))
            }
        }
    }

    /// Decision 10: surfaces a StatusFeedback. With no content canvas open, shows an auto-dismissing
    /// (~1.5s) non-blocking banner; with a canvas already open, shows a top-trailing corner badge on
    /// the open card instead.
    private func presentStatus(_ feedback: StatusFeedback) {
        // Never surface a status if the popup isn't showing (e.g. a `.failure` result dismissed it
        // before the effect threw); otherwise a detached banner would float with no bar.
        guard panel?.isVisible == true else { return }
        if modeStore.mode == .content {
            currentStatusBadge = feedback
            return
        }
        statusDismissTask?.cancel()
        modeStore.statusBanner = feedback
        statusDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: statusBubbleDurationNanoseconds)
            guard !Task.isCancelled else { return }
            self.modeStore.statusBanner = nil
        }
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
