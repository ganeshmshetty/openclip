// PopupWindowController.swift
// OpenClip
//
// Manages the window lifecycle, event tracking, positioning, and animation of the main floating popup panel.
// Owns the popup mode state machine (actions bar ↔ action-search palette ↔ native result card): search
// mode makes the panel key (a scoped exception to the never-key rule) and restores focus to the
// previous app on exit; content mode renders the result card inline on the panel and — since
// Task 14 — is also key, reusing the same enterKeyMode()/exitKeyMode() primitives as search, with
// Esc owned by the SwiftUI card (the controller-level key monitor stays observation-only in
// content mode, bar the one case where the card lost key). Content mode is also the one mode that
// survives everything but an explicit answer: `cardIsModal` suppresses every automatic dismissal
// (outside click, scroll, cursor distance, app switch) so the card lives until Copy, Paste or Esc.
// Implements the decision-8 ActionResult tree-walk (handleActionResult): presentation results render
// here, leaf effects route to DefaultActionResultHandler, and dismissal is decided once via
// ActionResult.dismissesPopup.
import AppKit
import SwiftUI
import Combine
import Core

@MainActor
public class PopupWindowController {
    var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    public var sourceAppBundleID: String? { currentContext?.sourceApp.bundleIdentifier }
    var currentActionContext: ActionContext?
    private var cardAbove = false
    /// Popup display mode (actions bar ↔ search palette ↔ result card), observed by PopupView.
    public let modeStore = PopupModeStore()
    private var cancellables = Set<AnyCancellable>()

    /// Records action usage for search recency ranking.
    private let usageStore = ActionUsageStore()
    /// Frontmost app before the panel became key (search or content); captured once per session in
    /// show(for:), reactivated on exitKeyMode/hide, cleared only by hide(). Internal for tests.
    var previousFrontmostApp: NSRunningApplication?

    /// Frame of the main bar prior to entering search mode, so exitSearch() can restore exact placement.
    private var preSearchFrame: NSRect?

    /// True when the current session was opened directly into search mode (e.g. via keyboard shortcut),
    /// so exitSearch() (Esc) dismisses the palette completely rather than falling back to the bar.
    public private(set) var openedDirectlyInSearch: Bool = false

    /// Monotonic timestamp recorded when a session starts (`show(for:)`). Used by
    /// `workspaceDidActivateApp` to suppress the race where macOS delivers a queued
    /// app-activation notification for the destination app within ~300 ms of the popup
    /// opening — common after a clipboard manager dismisses itself.
    var sessionShowTime: TimeInterval = 0

    private var hoveredAction: (any Action)?

    private var isMenuTracking = false

    /// Tracks whether a right-click mouse-down originated within the popup bar.
    private var isRightClickInProgress = false

    /// How the most recent bar/palette action was triggered (left-click vs right/⇧-click). Set by
    /// the mouse monitor on mouse-down and reset by hide(). Snapshotted into a `DeliveryContext`
    /// when an action performs — never read as live state after an await. Drives the standardized
    /// paste-vs-copy delivery decision (`ActionResultDelivery`).
    private var pendingClickIntent: ActionResultDelivery.ClickIntent = .primary

    /// The most recent bar/palette action's declared delivery (secondary outcome + per-click
    /// toasts). Set by the perform paths (`onWillPerformAction`, `runAction`,
    /// `runLoadingAction`) right before the action runs, consumed once by the next
    /// `deliverResult` snapshot (which clears it — single-use per perform), and reset by hide().
    /// Snapshotted into a `DeliveryContext` with `pendingClickIntent`, so `resolveDelivery` sees
    /// the action's declared delivery — never read as live state after an await. Internal for
    /// tests so a test can model the `onWillPerformAction` snapshot directly.
    var pendingDelivery: ActionDelivery? = nil

    /// The most recent bar/palette action's title, for the result card header. Set by the perform
    /// paths (`onWillPerformAction`, `runAction`, `runLoadingAction`) alongside `pendingDelivery`,
    /// consumed once by the next `deliverResult` snapshot (which clears it), reset by hide(). Internal
    /// for tests.
    var pendingActionTitle: String? = nil

    /// The most recent bar/palette action's display icon (customization-resolved, mirroring the bar
    /// row), for the result card header. Lifecycle mirrors `pendingActionTitle`. Internal for tests.
    var pendingActionIcon: ActionIcon? = nil

    /// In-flight delivery context snapshotted before an action performs, preserved across hide()
    /// so an asynchronous action that finishes after popup dismissal or app-switching delivers with
    /// its original context. Internal for tests.
    var inFlightDeliveryContext: DeliveryContext? = nil

    /// Provider for the current frontmost application. Defaults to NSWorkspace.shared.frontmostApplication.
    /// Injected for testing app-switching scenarios.
    var frontmostApplicationProvider: @MainActor () -> NSRunningApplication? = {
        NSWorkspace.shared.frontmostApplication
    }

    /// Probes whether the frontmost app supports Paste. Injected for tests.
    private let pasteProbe: PasteAvailabilityProbing

    /// The floating toast surface for statuses and the paste→copy "Copied" notice. Independent of
    /// the popup panel: it shows whether the popup is up or has already hidden. Injected for tests.
    let toastController: ToastPanelController

    /// The standalone floating panel hosting group sub-actions and AI tool presets.
    public let subBarController: SubBarPanelController

    /// The screen-space hover-tooltip surface shared with the sub-bar controller. Tooltips render
    /// in their own window above both bar panels so they escape panel clipping, flip above/below
    /// the hovered bar, and avoid the expanded sub-bar. Injected for tests.
    public let tooltipController: TooltipPanelController

    /// The resolved active actions for the current session, used for sub-action resolution.
    private var currentActions: [any Action]? = nil

    /// Frame of the popup during its most recent on-screen session (screen coords), captured right
    /// after each placement so toasts stay linked to where the popup actually was even after
    /// hide() — never falling back to the pointer. Internal for tests.
    var lastPopupFrame: NSRect?

    /// The settings store resolving the per-click result-delivery preference. Injected for tests.
    private let settingsStore: SettingsStore

    /// Session token for AI streaming deliveries, bumped by hide() and show(for:). Streaming
    /// closures are stamped with the session they were built under and dropped on mismatch, so
    /// chunks from an abandoned stream (popup dismissed mid-stream) can never flip a later
    /// session into content mode or re-stick isProcessingAI.
    public private(set) var aiSessionID = UUID()

    /// The live AI streaming task for the current session, registered by PopupView when it
    /// starts streaming and cancelled by hide() — session-scoped cancellation that does not
    /// depend on SwiftUI view teardown racing AppKit's hide().
    var activeStreamingTask: Task<Void, Never>?

    /// Active loading action task reference so clicking the loading toast can cancel in-flight execution.
    var activeLoadingTask: Task<Void, Never>?
    private var activeLoadingID: UUID?

    /// When true, distance-based auto-dismiss is suppressed so the popup stays visible
    /// during the onboarding sandbox experience.
    public var isOnboardingVisible: Bool = false

    /// Accumulator for trackpad scroll wheel displacement to avoid false-positive dismissals
    /// from resting palms or finger-lift micro-scrolls.
    private var accumulatedScrollDelta: CGFloat = 0

    public init(resultHandler: ActionResultHandler = DefaultActionResultHandler(),
                 pasteProbe: PasteAvailabilityProbing = PasteAvailabilityProbe(),
                 toastController: ToastPanelController = ToastPanelController(),
                 subBarController: SubBarPanelController = SubBarPanelController(),
                 tooltipController: TooltipPanelController = .shared,
                 settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.resultHandler = resultHandler
        self.pasteProbe = pasteProbe
        self.toastController = toastController
        self.subBarController = subBarController
        self.tooltipController = tooltipController
        self.settingsStore = settingsStore

        self.subBarController.onDismiss = { [weak self] in
            self?.modeStore.isSubBarActive = false
            self?.modeStore.activeSubGroupID = nil
        }

        modeStore.$isSubBarActive.sink { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if self.modeStore.mode == .actions {
                panel.pinBottomEdgeOnResize = self.modeStore.searchResultsAbove
            }
        }.store(in: &cancellables)
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

    public func show(for context: SelectionContext, pasteAvailable: Bool? = nil, initialMode: PopupMode = .actions) {
        show(for: context, pasteAvailable: pasteAvailable, preservingSessionID: nil, streamingTask: nil, initialMode: initialMode)
    }

    func show(for context: SelectionContext, pasteAvailable: Bool?, preservingSessionID: UUID?, streamingTask: Task<Void, Never>?, initialMode: PopupMode = .actions) {
        let aiSession: UUID
        if let preservingSessionID {
            aiSession = preservingSessionID
            aiSessionID = preservingSessionID
            activeStreamingTask = streamingTask
        } else {
            // A new session invalidates any still-running stream from the previous one: cancel its
            // task and bump the token so late chunks are dropped even before the old view unwinds.
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
            activeLoadingTask?.cancel()
            activeLoadingTask = nil
            aiSession = UUID()
            aiSessionID = aiSession
        }

        isMenuTracking = false
        currentContext = context
        sessionShowTime = ProcessInfo.processInfo.systemUptime

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
        panel.releasesBottomPinAfterGrowth = false
        panel.horizontalAnchor = .none
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        preSearchFrame = nil
        openedDirectlyInSearch = (initialMode == .search)

        let rawAlignment = settingsStore.get(SettingKey.popupAlignment)
        let alignment = PopupBarAlignment(rawValue: rawAlignment) ?? .left
        let rawVertical = settingsStore.get(SettingKey.popupVerticalPosition)
        let verticalPosition = PopupVerticalPosition(rawValue: rawVertical) ?? .auto

        // Pre-compute card direction from real screen position. Placement is the same for both
        // entry points: a palette opened by the shortcut is anchored on the selection and honors
        // the alignment / vertical-position preferences exactly like the bar the mouse opens —
        // it used to land in the middle of the main screen, ignoring both.
        let screen = PopupPositioner.screen(containing: context.cursorPosition) ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        // A palette opened directly by the hotkey renders at its remembered size from the first
        // frame (enterSearch() is not on this path), so restore it before the view is built; a
        // remembered palette may also be taller than the shared bar/palette cap.
        modeStore.searchPaletteSize = initialMode == .search ? rememberedSize(for: .palette, in: screenBounds) : nil
        panel.heightCap = initialMode == .search ? screenBounds.height : PopupMetrics.popupMaxHeight
        let probeWidth = initialMode == .search ? currentSearchPanelWidth : 320
        let tempFrame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: CGSize(width: probeWidth, height: 50),
            in: screenBounds,
            alignment: alignment,
            verticalPosition: verticalPosition
        )
        cardAbove = tempFrame.minY < screenBounds.minY + PopupMetrics.cardAboveThreshold

        modeStore.mode = initialMode
        PaletteRowShortcuts.setActive(initialMode == .search)
        modeStore.searchResultsAbove = cardAbove
        modeStore.subBarAbove = PopupPositioner.isPlacedAbove(frame: tempFrame, releasePoint: context.cursorPosition)
        // Probed before selection retrieval by the trigger sites and resolved before this frame,
        // so the bar/search gate Paste/Cut correctly on the first render. `nil` keeps them visible.
        modeStore.canPaste = pasteAvailable

        let activeActions = pasteAvailable == false
            ? availableActions.filter { !($0 is any PasteRequiringAction) }
            : availableActions
        self.currentActions = activeActions

        modeStore.inlineResults.removeAll()
        let inlineActions = activeActions.filter { $0.chrome.isInlineResult }
        let textHash = context.text.hashValue
        let evaluator = InlineResultEvaluator.shared

        for action in inlineActions {
            if let syncResult = evaluator.evaluateSynchronous(action: action, context: actionContext) {
                modeStore.inlineResults[action.id] = syncResult
            } else if let prewarmed = evaluator.prewarmedResult(for: action.id, textHash: textHash) {
                modeStore.inlineResults[action.id] = prewarmed
            } else {
                evaluator.startEvaluation(action: action, context: actionContext, sessionID: aiSession) { [weak self] result in
                    guard let self, let result, !result.isEmpty else { return }
                    self.modeStore.inlineResults[action.id] = result
                }
            }
        }

        let rootView = PopupView(
            actions: activeActions,
            allActions: activeActions,
            context: actionContext,
            initialAICardAboveBar: cardAbove,
            modeStore: modeStore,
            sessionID: aiSession,
            registerStreamingTask: { [weak self] task in
                self?.activeStreamingTask = task
            },
            onEnterSearch: { [weak self] frame in self?.enterSearch(buttonLocalFrame: frame) },
            onExitSearch: { [weak self] in self?.exitSearch() },
            onExitContent: { [weak self] in self?.exitContent() },
            onDismissContent: { [weak self] in self?.hide() },
            onCardDrag: { [weak self] phase in self?.handleCardDrag(phase) },
            onResize: { [weak self] edge, phase in self?.handleResize(edge, phase: phase) },
            onCardEffect: { [weak self] result in
                self?.performCardEffect(result)
            },
            onResult: { [weak self] result in
                self?.deliverResult(result)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onAIStateChange: { [weak self] active, _ in
                self?.setAIProcessing(active, session: aiSession)
            },
            onAIResult: { [weak self] text, isError, title, isStreaming in
                self?.showResultCard(text: text, isError: isError, title: title, isStreaming: isStreaming, session: aiSession)
            },
            onRequestSubBarToggle: { [weak self] action, index, frame in
                self?.handleSubBarToggle(for: action, index: index, frame: frame)
            },
            onRequestSubBarDwell: { [weak self] action, index, frame in
                self?.handleSubBarDwell(for: action, index: index, frame: frame)
            },
            onCancelSubBarDwell: { [weak self] in
                self?.handleCancelSubBarDwell()
            },
            onHoveredActionChanged: { [weak self] action in
                self?.updateHoveredAction(action)
            },
            onEnteredScopedSearch: { [weak self] action, frame in
                self?.enterScopedSearch(for: action, buttonLocalFrame: frame)
            },
            onPaginationAnchor: { [weak self] anchor in
                self?.panel?.horizontalAnchor = anchor
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            },
            onWillPerformAction: { [weak self] action in
                guard let self else { return }
                self.pendingDelivery = action.delivery
                self.pendingActionTitle = action.title
                self.pendingActionIcon = action.displayIcon(using: ActionCustomizationManager.shared)
                self.inFlightDeliveryContext = self.deliverySnapshot(for: action)
            },
            onRunLoadingAction: { [weak self] action in
                guard let self, let context = self.currentActionContext else { return }
                self.runLoadingAction(action, with: context, isSecondaryClick: self.pendingClickIntent == .secondary)
            },
            onRunAI: { [weak self] actionID in
                guard let self, let preset = AIServiceManager.shared.preset(forActionID: actionID) else { return }
                let prompt = AIServiceManager.shared.promptForPreset(preset)
                self.runAIPreset(prompt: prompt, title: preset.title)
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .primary },
            onShowTooltip: { [weak self] text, localFrame, theme, isDark in
                self?.presentTooltip(text: text, localFrame: localFrame, effectiveTheme: theme, isDark: isDark)
            },
            onHideTooltip: { [weak self] in
                self?.tooltipController.hide()
            }
        )
        panel.contentView = PopupPanel.ContentView(rootView: rootView)
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)

        // Compute card direction from real screen position using the actual rendered panel size.
        let calculatedFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: size, in: screenBounds, alignment: alignment, verticalPosition: verticalPosition)
        positionPanel(panel, size: size, for: context, alignment: alignment, verticalPosition: verticalPosition)
        cardAbove = calculatedFrame.minY < screenBounds.minY + PopupMetrics.cardAboveThreshold
        modeStore.searchResultsAbove = cardAbove
        modeStore.subBarAbove = PopupPositioner.isPlacedAbove(frame: calculatedFrame, releasePoint: context.cursorPosition)
        lastPopupFrame = panel.frame
        // Placement is fixed; any subsequent content-driven width change (search palette,
        // pagination) must re-center rather than drift off the cursor.
        panel.horizontalAnchor = .center
        // Content-driven growth keeps the panel's bottom edge fixed when the popup sits low on
        // screen — same anchor rule as search/content mode. A palette opened directly is already
        // placed at its size; its later changes (the list shrinking as a query narrows) must keep
        // the field at the top fixed, so it is not pinned.
        panel.pinBottomEdgeOnResize = initialMode == .search ? false : cardAbove
        panel.orderFront(nil)
        
        setupMonitors()

        if initialMode == .search {
            enterKeyMode()
            Task { @MainActor in
                await Task.yield()
                self.focusSearchField()
            }
            scheduleKeepPanelOnScreen()
        }
    }

    public var isVisible: Bool { (panel?.isVisible == true) || (currentContext != nil) }

    /// Starts a session without creating AppKit window monitors or ordering windows on screen. Internal for tests.
    func startTestSession(for context: SelectionContext, pasteAvailable: Bool? = nil, initialMode: PopupMode = .actions) {
        isMenuTracking = false
        currentContext = context
        captureFrontmostAppIfNeeded()
        let actionContext = ActionContext(selection: context, modifiers: [])
        currentActionContext = actionContext
        modeStore.mode = initialMode
        modeStore.canPaste = pasteAvailable
        openedDirectlyInSearch = (initialMode == .search)
    }

    /// Hotkey-driven toggle: dismisses the popup if already visible.
    public func toggleMode() {
        guard panel?.isVisible == true else { return }
        hide()
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
        guard let panel else { return }
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
    public func enterSearch(with scope: SearchScope? = nil, buttonLocalFrame: CGRect? = nil) {
        guard let panel, panel.isVisible else { return }
        if preSearchFrame == nil {
            preSearchFrame = panel.frame
        }
        subBarController.hide()
        modeStore.isSubBarActive = false
        modeStore.activeSubGroupID = nil
        if modeStore.mode != .search || scope != nil {
            modeStore.scope = scope
        }
        if modeStore.mode != .search {
            // Fresh entry (not a scope hop): the palette may open as tall as its remembered
            // maximum, which can exceed the shared bar/palette cap.
            modeStore.searchPaletteSize = rememberedSize(for: .palette, in: screenBounds(for: panel))
            modeStore.isSurfaceUserSized = false
            panel.heightCap = screenBounds(for: panel).height
            // The entry growth keeps the panel's bottom edge fixed when the popup sits low on screen
            // (the palette must extend upward to stay on it); see PopupPanel.setFrame. That pin is
            // one-shot: once the palette is up, its height follows the result count, and the field
            // at its top must stay put — later changes anchor the top edge. A scope hop is not a
            // fresh entry and leaves the anchoring alone.
            panel.pinBottomEdgeOnResize = modeStore.searchResultsAbove
            panel.releasesBottomPinAfterGrowth = modeStore.searchResultsAbove
        }
        modeStore.mode = .search
        PaletteRowShortcuts.setActive(true)

        if let buttonLocalFrame {
            panel.horizontalAnchor = .none
            let barFrame = preSearchFrame ?? panel.frame
            preSearchFrame = barFrame
            let buttonScreenMidX = barFrame.minX + buttonLocalFrame.midX
            let searchPanelWidth = currentSearchPanelWidth
            let screen = panel.screen ?? NSScreen.main
            let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let clampedMidX = PopupPositioner.searchPaletteMidX(
                buttonScreenMidX: buttonScreenMidX,
                searchWidth: searchPanelWidth,
                barMaxX: barFrame.maxX,
                screenBounds: screenBounds
            )

            panel.setFrame(CGRect(x: clampedMidX - searchPanelWidth / 2, y: panel.frame.origin.y, width: searchPanelWidth, height: panel.frame.height), display: false)
        }
        panel.horizontalAnchor = .center

        enterKeyMode()
        // Explicitly make the search field first responder on the next run-loop turn. A @FocusState
        // request issued during the mode-change render can be silently dropped on macOS before the
        // panel has finished becoming key (worst on the click-path: the click that opened search).
        Task { @MainActor in
            await Task.yield()
            self.focusSearchField()
        }
        scheduleKeepPanelOnScreen()
    }

    /// The panel width for the palette: its remembered width when there is one, else the default
    /// column, plus the shadow ring on both sides.
    private var currentSearchPanelWidth: CGFloat {
        (modeStore.searchPaletteSize?.width ?? PopupMetrics.searchPanelContentWidth) + 2 * PopupMetrics.popupShadowInset
    }

    /// The hosting view grows the panel to the palette on its own, after the current run-loop turn
    /// (and sometimes a display pass later); a remembered palette can be tall enough for that
    /// growth to run off a screen edge, so nudge it back once the growth has landed. Same two
    /// retries as `showResultCard`.
    private func scheduleKeepPanelOnScreen() {
        DispatchQueue.main.async { [weak self] in self?.keepPanelOnScreen() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.keepPanelOnScreen() }
    }

    /// Opens the palette scoped to a bar row's sub-actions. The parent action supplies its children
    /// via `SubActionProviding` (core, id/`.ai`-driven); resolution happens here so the view never
    /// type-checks against the action catalog.
    private func enterScopedSearch(for action: any Action, buttonLocalFrame: CGRect? = nil) {
        guard let actionContext = currentActionContext else { return }
        let children = SubActionResolver().subActions(
            of: action,
            in: ActionCoordinator.shared.searchCatalog(for: actionContext)
        )
        enterSearch(with: SearchScope(parent: action, children: children), buttonLocalFrame: buttonLocalFrame)
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
    /// keyboard focus back to the source app. Never hides the popup unless the session was opened
    /// directly in search mode (e.g. via keyboard shortcut). The bottom-edge pin is kept
    /// active through the shrink so the bar returns to the field's spot (results-above case);
    /// it is cleared by hide() and the next show(for:).
    public func exitSearch() {
        guard modeStore.mode == .search else { return }
        if openedDirectlyInSearch {
            hide()
            return
        }
        modeStore.scope = nil
        modeStore.mode = .actions
        PaletteRowShortcuts.setActive(false)
        // Return to the bar keeps the field-anchoring rule active for hover-preview/banner growth
        // (strip renders above the bar when the popup sits low), so set it explicitly rather than
        // leaving the search-mode value behind. Cleared by show()/hide() before placement.
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        panel?.releasesBottomPinAfterGrowth = false
        if let preSearchFrame, let panel {
            panel.horizontalAnchor = .none
            // The collapse keeps the bottom edge (results above) or the top edge (results below).
            // The top never moves during a session, but a palette whose height followed the result
            // count moved its bottom edge — put it back on the bar's original bottom first, so the
            // bar lands exactly where it was.
            let restoredY = modeStore.searchResultsAbove ? preSearchFrame.minY : panel.frame.minY
            panel.setFrame(CGRect(x: preSearchFrame.origin.x, y: restoredY, width: preSearchFrame.width, height: panel.frame.height), display: false)
            panel.horizontalAnchor = .center
        }
        preSearchFrame = nil
        // After the frame restore above, so a resized (tall) palette is not clamped mid-collapse;
        // the bar's own shrink requests a height well under the cap.
        modeStore.searchPaletteSize = nil
        modeStore.isSurfaceUserSized = false
        resizeAnchor = nil
        panel?.heightCap = PopupMetrics.popupMaxHeight
        exitKeyMode() // reactivates previousFrontmostApp but keeps it for the session
    }

    // MARK: - AI Result Card

    /// True while the result card is on screen AND the user has dragged it aside to keep it open.
    /// An un-dragged result card remains standard and dismisses on outside clicks.
    public var cardIsModal: Bool { modeStore.mode == .content && hasUserMovedCard }
    public private(set) var hasUserMovedCard: Bool = false

    /// Applies a streaming "processing" flag update, but only for the session the update
    /// belongs to. A stale stream (popup dismissed mid-stream, superseded by a new selection)
    /// must never re-stick isProcessingAI after hide() cleared it.
    func setAIProcessing(_ active: Bool, session: UUID) {
        guard session == aiSessionID else { return }
        modeStore.isProcessingAI = active
    }

    /// Shows an action's returned text (or error) in the native result card, entering content
    /// mode and making the panel key so Esc can collapse the card. Any text-returning action
    /// renders here — AI presets stream into it via `onAIResult`, extensions land via the
    /// delivery snapshot with their own icon. Paste/Copy are explicit user requests routed
    /// through `performCardEffect`, so they bypass the paste-vs-copy re-decision — an explicit
    /// Paste always pastes. The selection the action ran on is carried in the payload so the card
    /// can render a character-level diff of what changed. Probes (AX) whether the target app can
    /// paste so the card can hide its Paste button; the probe targets the captured source app,
    /// never OpenClip itself. Deliveries
    /// are session-stamped: a chunk from an abandoned stream is dropped instead of hijacking the
    /// current popup into content mode. Internal for tests.
    func showResultCard(text: String, isError: Bool, title: String, icon: ActionIcon? = nil, isStreaming: Bool = false, session: UUID) {
        guard session == aiSessionID else { return }
        if toastController.isLoading {
            toastController.hide()
        }
        modeStore.isProcessingAI = isStreaming
        // The selection the action ran on rides along so the card can diff input → output.
        modeStore.resultCard = ResultCardPayload(
            text: text,
            isError: isError,
            title: title,
            icon: icon,
            isStreaming: isStreaming,
            original: currentActionContext?.selection.text
        )
        if modeStore.mode != .content {
            hasUserMovedCard = false
            PaletteRowShortcuts.setActive(false)
            panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
            panel?.horizontalAnchor = .center
            // A remembered (or later resized) card may be far taller than the bar/palette cap:
            // let the panel grow as tall as the screen; the card's own clamps keep it on-screen.
            if let panel { panel.heightCap = screenBounds(for: panel).height }
            modeStore.resultCardSize = rememberedSize(for: .card)
            modeStore.isSurfaceUserSized = false
            modeStore.mode = .content
            enterKeyMode()
        }

        // Tell the hosting view its intrinsic content size has changed so AppKit
        // re-measures on the next display cycle (the mode change schedules a SwiftUI
        // re-evaluation, but NSHostingView won't re-measure without this nudge).
        fitPanelToContent()
        // Retry after the current AppKit display cycle completes — DispatchQueue.main.async
        // fires after the run-loop turn, unlike Task.yield() which only yields in the
        // cooperative pool without guaranteeing a display pass.
        DispatchQueue.main.async { [weak self] in
            self?.fitPanelToContent()
        }
        // Safety-net retry for the first content-mode entry where SwiftUI swaps
        // the entire view tree (bar → ResultCardView) and needs an extra
        // layout pass to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.modeStore.mode == .content else { return }
            self.fitPanelToContent()
        }
    }

    /// Re-measures the hosting view and grows/shrinks the panel to its content, then nudges the
    /// panel back inside the screen: a card opening at a remembered size can be far taller than
    /// the bar it replaces, so the anchored growth may otherwise run off a screen edge.
    private func fitPanelToContent() {
        guard let contentView = panel?.contentView else { return }
        contentView.invalidateIntrinsicContentSize()
        contentView.layoutSubtreeIfNeeded()
        resizePanel(to: sanitizedPopupSize(contentView.fittingSize))
        keepPanelOnScreen()
    }

    /// Moves the panel the minimum distance needed to sit inside its screen (by `popupPadding`)
    /// while a resizable surface shows. Only automatic placement is corrected: a card the user
    /// dragged stays where they put it.
    private func keepPanelOnScreen() {
        guard let panel, panel.isVisible, resizableSurface != nil, !hasUserMovedCard else { return }
        let bounds = screenBounds(for: panel).insetBy(dx: PopupMetrics.popupPadding, dy: PopupMetrics.popupPadding)
        var origin = panel.frame.origin
        origin.x = max(min(origin.x, bounds.maxX - panel.frame.width), bounds.minX)
        origin.y = max(min(origin.y, bounds.maxY - panel.frame.height), bounds.minY)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Resizable Surfaces

    /// The popup surfaces with resize handles. Each has its own floor and remembers its own size
    /// under its own keys; the geometry, the panel handling and the persistence flow are shared.
    private enum ResizableSurface {
        case card
        case palette

        var minSize: CGSize {
            switch self {
            case .card:
                return CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight)
            case .palette:
                return CGSize(width: PopupMetrics.searchPaletteMinWidth, height: PopupMetrics.searchPaletteMinHeight)
            }
        }

        var widthKey: SettingKey<Double> {
            switch self {
            case .card: return SettingKey.resultCardWidth
            case .palette: return SettingKey.searchPaletteWidth
            }
        }

        var heightKey: SettingKey<Double> {
            switch self {
            case .card: return SettingKey.resultCardHeight
            case .palette: return SettingKey.searchPaletteHeight
            }
        }
    }

    /// The resizable surface currently on screen, if the popup is showing one.
    private var resizableSurface: ResizableSurface? {
        switch modeStore.mode {
        case .content: return .card
        case .search: return .palette
        case .actions: return nil
        }
    }

    private func liveSize(for surface: ResizableSurface) -> CGSize? {
        switch surface {
        case .card: return modeStore.resultCardSize
        case .palette: return modeStore.searchPaletteSize
        }
    }

    private func setLiveSize(_ size: CGSize?, for surface: ResizableSurface) {
        switch surface {
        case .card: modeStore.resultCardSize = size
        case .palette: modeStore.searchPaletteSize = size
        }
    }

    /// The size the user last resized `surface` to, fitted to `screenBounds` (the panel's screen
    /// when nil); nil until the surface has been resized once, so it keeps its default sizing.
    private func rememberedSize(for surface: ResizableSurface, in screenBounds: CGRect? = nil) -> CGSize? {
        let width = settingsStore.get(surface.widthKey)
        let height = settingsStore.get(surface.heightKey)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let bounds = screenBounds ?? panel.map { self.screenBounds(for: $0) } ?? Self.fallbackScreenBounds
        return PopupResizeGeometry.fit(CGSize(width: width, height: height), minSize: surface.minSize, in: bounds)
    }

    private static let fallbackScreenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)

    private func screenBounds(for panel: PopupPanel) -> CGRect {
        panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? Self.fallbackScreenBounds
    }

    /// Where the panel sat, and where the cursor was, when the current card drag began. Nil while
    /// no drag is in flight.
    private var cardDragAnchor: (mouse: CGPoint, origin: CGPoint)?

    /// Moves the panel with the cursor while the card's header handle is dragged. The move is
    /// computed from the *absolute* cursor position against the anchor taken at `.began`, never
    /// from the gesture's own translation: the window moves out from under the pointer, so a
    /// translation-based move would fight itself and crawl. `mouseLocation` is injectable so the
    /// geometry is testable without a real cursor. Internal for tests.
    func handleCardDrag(_ phase: ResultCardDragPhase, mouseLocation: CGPoint? = nil) {
        guard let panel else { return }
        let mouse = mouseLocation ?? NSEvent.mouseLocation
        switch phase {
        case .began:
            panel.prepareForUserDrag()
            cardDragAnchor = (mouse: mouse, origin: panel.frame.origin)
        case .changed:
            guard let anchor = cardDragAnchor else { return }
            panel.setFrameOrigin(CGPoint(x: anchor.origin.x + (mouse.x - anchor.mouse.x),
                                         y: anchor.origin.y + (mouse.y - anchor.mouse.y)))
        case .ended:
            cardDragAnchor = nil
            panel.endUserDrag()
            hasUserMovedCard = true
        }
    }

    // MARK: - Resize

    /// Where the cursor was, how big the surface was, and which surface it was when the current
    /// resize began. Nil while no resize is in flight; `resizePanel` reads it to keep
    /// content-driven size reports anchored at the surface's top-left corner for the duration.
    private var resizeAnchor: (mouse: CGPoint, size: CGSize, surface: ResizableSurface)?

    /// Resizes the surface on screen (result card or search palette) as one of its handles is
    /// dragged. Mirrors `handleCardDrag`: the new size comes from the *absolute* cursor position
    /// against the anchor taken at `.began` (the dragged edge moves out from under the pointer, so
    /// the gesture's own translation would fight it), the surface's top-left corner stays fixed,
    /// and the size is clamped to the surface minimum and to the screen. `.ended` remembers the
    /// size under the surface's keys. `mouseLocation` is injectable so the geometry is testable
    /// without a real cursor. Internal for tests.
    func handleResize(_ edge: PopupResizeEdge, phase: ResultCardDragPhase, mouseLocation: CGPoint? = nil) {
        guard let panel, let surface = resizableSurface else { return }
        let mouse = mouseLocation ?? NSEvent.mouseLocation
        switch phase {
        case .began:
            // Same panel state as a move: no hover-driven click-through mid-drag, and neither
            // re-centering nor bottom-pinning fighting the top-left-anchored frames set below.
            panel.prepareForUserDrag()
            panel.pinBottomEdgeOnResize = false
            panel.releasesBottomPinAfterGrowth = false
            // The drag starts from the size on screen — smaller than the remembered maximum when
            // the content did not need all of it — so the handle stays under the pointer. From
            // here on the surface renders the dragged size verbatim, for the rest of its session.
            modeStore.isSurfaceUserSized = true
            resizeAnchor = (mouse: mouse, size: currentSurfaceSize(in: panel), surface: surface)
        case .changed:
            guard let anchor = resizeAnchor, anchor.surface == surface else { return }
            let proposed = PopupResizeGeometry.size(
                from: anchor.size, edge: edge, anchorMouse: anchor.mouse, mouse: mouse)
            let size = PopupResizeGeometry.clamp(
                proposed,
                minSize: surface.minSize,
                panelTopLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY),
                screenBounds: screenBounds(for: panel))
            applySize(size, for: surface, to: panel)
        case .ended:
            guard let anchor = resizeAnchor, anchor.surface == surface else { return }
            resizeAnchor = nil
            panel.endUserDrag()
            // The dragged size is what the surface keeps until it closes (`isSurfaceUserSized`
            // stays set), and the maximum the next one opens with.
            if let size = liveSize(for: surface) {
                settingsStore.set(surface.widthKey, value: Double(size.width))
                settingsStore.set(surface.heightKey, value: Double(size.height))
            }
        }
    }

    /// The surface's on-screen size derived from the panel frame (the panel is the surface plus
    /// the transparent shadow ring on every side). A surface's default size is never reported to
    /// the controller, so this is how the first resize of a session learns where it starts.
    private func currentSurfaceSize(in panel: PopupPanel) -> CGSize {
        let ring = 2 * PopupMetrics.popupShadowInset
        return CGSize(width: panel.frame.width - ring, height: panel.frame.height - ring)
    }

    /// Applies a size: the surface reads it from the store, and the panel is set to the surface
    /// plus its shadow ring with the top-left corner fixed (the handles sit on the right/bottom
    /// edges). The hosting view's own top-anchored auto-resize then lands on this same frame.
    private func applySize(_ size: CGSize, for surface: ResizableSurface, to panel: PopupPanel) {
        setLiveSize(size, for: surface)
        let ring = 2 * PopupMetrics.popupShadowInset
        let panelSize = CGSize(width: size.width + ring, height: size.height + ring)
        panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.maxY - panelSize.height,
                              width: panelSize.width, height: panelSize.height), display: true)
    }

    /// Collapses the result card back to the actions bar. Never hides the popup.
    public func exitContent() {
        guard modeStore.mode == .content else { return }
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        resizeAnchor = nil
        hasUserMovedCard = false
        modeStore.mode = .actions
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        panel?.heightCap = PopupMetrics.popupMaxHeight
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

    /// Resize the panel to its content, anchored the same way `PopupPanel.setFrame` anchors the
    /// hosting view's own resizes: a resize drag in flight keeps the surface's top-left corner;
    /// otherwise the panel's live bottom-edge pin decides (pinned when the popup sits low on screen,
    /// so growth extends upward; else the top edge stays). Horizontal re-centering and screen/height
    /// clamping are handled by `PopupPanel.setFrame`, the single funnel both paths go through.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        let size = sanitizedPopupSize(proposedSize)
        let current = panel.frame.size
        if abs(current.width - size.width) < 1, abs(current.height - size.height) < 1 { return }
        if resizeAnchor != nil {
            // A resize handle is being dragged: the surface's top-left corner is the fixed point.
            panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.maxY - size.height,
                                  width: size.width, height: size.height), display: true)
        } else if panel.pinBottomEdgeOnResize {
            // Bottom edge pinned (popup low on screen): keep it fixed, grow upward.
            panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.minY,
                                  width: size.width, height: size.height), display: true)
        } else {
            // Keep the top edge fixed, grow downward.
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

    private func positionPanel(_ panel: PopupPanel, size: CGSize, for context: SelectionContext, alignment: PopupBarAlignment = .left, verticalPosition: PopupVerticalPosition = .auto) {
        let screen = PopupPositioner.screen(containing: context.cursorPosition) ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: size,
            in: screenBounds,
            alignment: alignment,
            verticalPosition: verticalPosition
        )
        panel.setFrame(frame, display: true)
    }

    public func hide() {
        // End the AI session first: cancel the live stream and invalidate its token so any
        // chunk already in flight is dropped instead of re-flipping state after the resets below.
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeLoadingTask?.cancel()
        activeLoadingTask = nil
        activeLoadingID = nil
        InlineResultEvaluator.shared.cancelSession(aiSessionID)
        aiSessionID = UUID()

        if toastController.currentFeedback?.keepVisible == true || toastController.isLoading {
            toastController.hide()
        }
        subBarController.hide()
        tooltipController.hide()
        currentActions = nil
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.searchPaletteSize = nil
        modeStore.isSurfaceUserSized = false
        modeStore.canPaste = nil
        modeStore.inlineResults.removeAll()
        // A dismissed session must not leak its click intent into the next one (keyboard-driven
        // runs and any later snapshot read the last intent; force-copy must never persist). The
        // declared delivery is snapshotted per-perform, so a stale value must not leak either.
        pendingClickIntent = .primary
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        accumulatedScrollDelta = 0
        isRightClickInProgress = false
        modeStore.isProcessingAI = false
        modeStore.mode = .actions
        PaletteRowShortcuts.setActive(false)
        modeStore.isSubBarActive = false
        modeStore.activeSubGroupID = nil
        modeStore.scope = nil
        panel?.pinBottomEdgeOnResize = false
        panel?.releasesBottomPinAfterGrowth = false
        panel?.horizontalAnchor = .none
        panel?.heightCap = PopupMetrics.popupMaxHeight
        panel?.endUserDrag()
        cardDragAnchor = nil
        resizeAnchor = nil
        hasUserMovedCard = false
        preSearchFrame = nil
        openedDirectlyInSearch = false
        sessionShowTime = 0
        panel?.ignoresMouseEvents = false // clear any hover-driven click-through from the last session
        exitKeyMode() // allowsKey=false + reactivate previousFrontmostApp
        previousFrontmostApp = nil // hide() is the only thing that ends the key-mode session
        panel?.orderOut(nil)
        removeMonitors()
        currentContext = nil
        currentActionContext = nil
        hoveredAction = nil
        isMenuTracking = false
        PopupHoverState.shared.location = nil
        SubBarHoverState.shared.location = nil
    }

    /// Cancels any in-flight background tasks (loading actions and AI streaming) and hides the toast.
    @MainActor
    public func cancelActiveTasks() {
        if activeLoadingTask != nil || activeStreamingTask != nil {
            Log.presentation.info("Cancelling active in-flight task(s) via loading toast")
        }
        activeLoadingTask?.cancel()
        activeLoadingTask = nil
        activeLoadingID = nil
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        inFlightDeliveryContext = nil
        modeStore.isProcessingAI = false
        toastController.hide()
    }
    
    private func setupMonitors() {
        removeMonitors()

        let canMonitorGlobally = PermissionManager.shared.isAccessibilityGranted
        PopupHoverState.shared.usesGlobalMouseMonitoring = canMonitorGlobally
        SubBarHoverState.shared.usesGlobalMouseMonitoring = canMonitorGlobally
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidActivateApp(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceActiveSpaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Runs the palette row a global ⌘-digit hot key points at (1-based), returning false when
    /// there is no palette or no such row. The row list lives in the SwiftUI palette, so this
    /// reaches it through the catcher view mounted in the panel — the same walk `focusSearchField`
    /// uses to find the text field. Internal for tests.
    func runPaletteRow(_ row: Int) -> Bool {
        guard modeStore.mode == .search, let panel,
              let catcher = Self.findCommandDigitCatcher(in: panel.contentView) else { return false }
        return catcher.run(row: row)
    }

    private static func findCommandDigitCatcher(in view: NSView?) -> CommandDigitCatcher.CatcherView? {
        guard let view else { return nil }
        if let catcher = view as? CommandDigitCatcher.CatcherView { return catcher }
        for subview in view.subviews {
            if let found = findCommandDigitCatcher(in: subview) { return found }
        }
        return nil
    }

    func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }
        
        switch event.type {
        case .mouseMoved:
            let cursorLoc = NSEvent.mouseLocation
            updatePopupHover(at: cursorLoc)
            updateSubBarHover(at: cursorLoc)
            // Distance dismissal suspends in search mode (typing elsewhere must not dismiss the
            // palette), while the AI result card is open (modal), while AI is actively processing,
            // and while onboarding is visible (sandbox experience); it is active otherwise.
            let distanceDismissActive = modeStore.mode != .search && modeStore.mode != .content && !modeStore.isProcessingAI && !isOnboardingVisible
            if distanceDismissActive, let panel = panel {
                let frame = panel.frame
                let screenBounds = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
                let dismissalLimit = PopupMetrics.dismissalDistance(for: screenBounds)

                let dxMain = max(0, max(frame.minX - cursorLoc.x, cursorLoc.x - frame.maxX))
                let dyMain = max(0, max(frame.minY - cursorLoc.y, cursorLoc.y - frame.maxY))
                let distMain = hypot(dxMain, dyMain)

                let dist: CGFloat
                if subBarController.isShowing {
                    let subFrame = subBarController.panelFrame
                    // Safe hover pathway / corridor between main panel and sub-bar
                    let corridorMinX = min(frame.minX, subFrame.minX) - 16.0
                    let corridorMaxX = max(frame.maxX, subFrame.maxX) + 16.0
                    let corridorMinY = min(frame.minY, subFrame.minY) - 16.0
                    let corridorMaxY = max(frame.maxY, subFrame.maxY) + 16.0
                    let corridorRect = CGRect(x: corridorMinX, y: corridorMinY, width: corridorMaxX - corridorMinX, height: corridorMaxY - corridorMinY)

                    if corridorRect.contains(cursorLoc) {
                        dist = 0.0
                    } else {
                        let dxSub = max(0, max(subFrame.minX - cursorLoc.x, cursorLoc.x - subFrame.maxX))
                        let dySub = max(0, max(subFrame.minY - cursorLoc.y, cursorLoc.y - subFrame.maxY))
                        dist = min(distMain, hypot(dxSub, dySub))
                    }
                } else {
                    dist = distMain
                }

                if dist > dismissalLimit {
                    hide()
                }
            }
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            // Content test, not frame test: clicks in the transparent shadow ring dismiss the
            // popup like any outside click (the ring only hosts the SwiftUI drop shadow).
            let inMain = isOverPanelContent(clickLoc)
            let inSub = subBarController.isShowing && subBarController.isOverContent(clickLoc)
            // Capture the modifier state at click time so the action that runs on mouse-up (via the
            // SwiftUI Button) delivers as a copy when ⇧ is held.
            let isShift = event.modifierFlags.contains(.shift)
            pendingClickIntent = isShift ? .secondary : .primary
            if !inMain && !inSub && !cardIsModal {
                hide()
            }
        case .rightMouseDown:
            // Right-click down: prepare force-copy intent and mark right-click in progress.
            // Execution waits for rightMouseUp (matching standard button click-release semantics).
            let clickLoc = NSEvent.mouseLocation
            let inMain = isOverPanelContent(clickLoc)
            let inSub = subBarController.isShowing && subBarController.isOverContent(clickLoc)
            if inMain || inSub {
                pendingClickIntent = .secondary
                isRightClickInProgress = true
            } else {
                isRightClickInProgress = false
                if !cardIsModal { hide() }
            }
        case .rightMouseUp:
            guard isRightClickInProgress else { break }
            isRightClickInProgress = false
            let clickLoc = NSEvent.mouseLocation
            let inBar = isOverPanelContent(clickLoc)
            if inBar, let hoveredAction, let actionContext = currentActionContext, modeStore.mode == .actions {
                let isGroup = hoveredAction.gesturePolicy.singleClick == .openSubActions || hoveredAction.chrome.launchesAI
                if isGroup {
                    enterScopedSearch(for: hoveredAction)
                } else {
                    runAction(hoveredAction, with: actionContext, isSecondaryClick: true)
                }
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

            let rawDelta = hypot(event.scrollingDeltaX, event.scrollingDeltaY)
            let delta = event.hasPreciseScrollingDeltas ? rawDelta : (rawDelta > 0 || event.deltaY != 0 ? 12.0 : 0.0)

            if event.phase == .began {
                accumulatedScrollDelta = delta
            } else if event.phase == .ended || event.phase == .cancelled {
                accumulatedScrollDelta = 0
            } else {
                accumulatedScrollDelta += delta
            }

            if accumulatedScrollDelta >= 12.0 {
                accumulatedScrollDelta = 0
                hide()
            }
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
                // Esc belongs to the card component (SwiftUI .onKeyPress) — do NOT handle it here
                // while the panel is key, or it double-fires on top of SwiftUI (M8). The card now
                // survives a click into another app, though, and a panel that lost key never sees
                // the keystroke: that is the one case the monitor answers Esc itself.
                if event.keyCode == 53, panel?.isKeyWindow != true {
                    hide()
                }
                return
            }
            // Sub-bar Escape: when a sub-bar is open, Escape closes it instead of
            // dismissing the entire popup. The next Escape will dismiss the popup.
            if (subBarController.isShowing || modeStore.isSubBarActive), event.keyCode == 53 {
                subBarController.hide()
                modeStore.isSubBarActive = false
                modeStore.activeSubGroupID = nil
                return
            }
            hide()
        default:
            break
        }
    }

    /// Whether the screen point is over the popup's *interactive content* — the panel frame minus
    /// the transparent shadow ring. The ring only hosts the SwiftUI drop shadow, so clicks and
    /// right-clicks there must behave like clicks outside the popup (dismiss + pass through),
    /// never like clicks on the bar. Replaces every former `panel.frame.contains(...)` check,
    /// which silently swallowed shadow clicks: the panel is topmost at those pixels, so the click
    /// arrived as a local event, counted as "in the bar", and reached no app at all.
    /// Internal (not private) so tests can pin the ring-is-not-content contract.
    func isOverPanelContent(_ screenLocation: CGPoint) -> Bool {
        guard let panel, panel.isVisible, let contentView = panel.contentView,
              panel.frame.contains(screenLocation) else { return false }
        let windowPoint = panel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        if contentView is PopupPanel.ContentView {
            return PopupPanel.ContentView.isInsideClickableRegion(point: contentPoint, bounds: contentView.bounds)
        }
        return contentView.bounds.contains(contentPoint)
    }

    func updatePopupHover(at screenLocation: CGPoint) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else {
            PopupHoverState.shared.location = nil
            return
        }

        // Dynamic click-through: while the pointer is over the transparent shadow ring, the panel
        // ignores mouse events entirely so ring clicks genuinely reach the app underneath (the
        // global monitor still observes them and dismisses the popup). Gated on global monitoring:
        // without it the local monitor is the only way to notice the pointer re-entering the
        // content area, and ignoring events would strand the panel permanently inert.
        let overContent = isOverPanelContent(screenLocation)
        if PopupHoverState.shared.usesGlobalMouseMonitoring, !panel.isUserDragging {
            panel.ignoresMouseEvents = !overContent
        }
        if overContent {
            NSCursor.arrow.set()
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
        PopupHoverState.shared.location = point
    }

    func updateSubBarHover(at screenLocation: CGPoint) {
        guard subBarController.isShowing else {
            SubBarHoverState.shared.location = nil
            return
        }

        let subPanel = subBarController.panel
        guard subPanel.isVisible, let contentView = subPanel.contentView else {
            SubBarHoverState.shared.location = nil
            return
        }

        let overContent = subBarController.isOverContent(screenLocation)
        if SubBarHoverState.shared.usesGlobalMouseMonitoring {
            subPanel.ignoresMouseEvents = !overContent
        }
        if overContent {
            NSCursor.arrow.set()
        }

        let windowPoint = subPanel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        if contentView.bounds.contains(contentPoint) {
            let y = contentView.isFlipped ? contentPoint.y : contentView.bounds.height - contentPoint.y
            let point = CGPoint(x: contentPoint.x, y: y)
            if point != SubBarHoverState.shared.location {
                SubBarHoverState.shared.location = point
            }
        } else {
            SubBarHoverState.shared.location = nil
        }

        guard !subBarController.isPinned else { return }

        // Is the pointer anywhere over the sub-bar window (including comfort margin)?
        let overSubBar = subBarController.panelFrame.insetBy(dx: -4, dy: -4).contains(screenLocation)

        // Is the pointer over the parent group action OR an immediate neighbor in the main bar?
        let isNearAction: Bool = {
            guard isOverPanelContent(screenLocation), let hoveredAction, let actions = currentActions else {
                return false
            }
            if hoveredAction.id == subBarController.activeState?.groupID {
                return true
            }
            if let currentIndex = actions.firstIndex(where: { $0.id == hoveredAction.id }) {
                return subBarController.isImmediateNeighbor(actionIndex: currentIndex)
            }
            return false
        }()

        if overSubBar || isNearAction {
            subBarController.cancelGrace()
        } else if isOverPanelContent(screenLocation) {
            // Pointer is over a distant action on the main bar: close the sub-bar!
            subBarController.hide()
        } else {
            // Pointer has left both the sub-bar and the main bar (moving across the gap or away)
            subBarController.startGrace()
        }
    }

    private func handleCancelSubBarDwell() {
        if let hoveredAction, let actions = currentActions,
           let currentIndex = actions.firstIndex(where: { $0.id == hoveredAction.id }),
           subBarController.isImmediateNeighbor(actionIndex: currentIndex) {
            // Pointer is over an immediate neighbor action: cancel pending dwell without starting grace!
            subBarController.cancelDwell(startGrace: false)
            subBarController.cancelGrace()
            return
        }
        subBarController.cancelDwell()
    }
    
    @objc private func appDidDeactivate() {
        // A right-click fires didResignActiveNotification before rightMouseUp arrives; suppressing
        // hide() here lets the right-click path complete on mouse-up as intended. The result card
        // outlives focus changes entirely (`cardIsModal`).
        if !isMenuTracking && !isRightClickInProgress && !cardIsModal {
            hide()
        }
    }

    @objc private func workspaceDidActivateApp(_ notification: Notification) {
        guard let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            ?? NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        if let sourceBundleID = currentContext?.sourceApp.bundleIdentifier,
           app.bundleIdentifier == sourceBundleID {
            return
        }
        // Modal result cards survive focus changes (parity with appDidDeactivate).
        if cardIsModal { return }
        // Grace period: when a clipboard manager (Paste, Raycast, Maccy) dismisses itself, macOS
        // delivers a queued didActivateApplication for the destination app. If the popup just
        // opened (< 300 ms ago) this is almost certainly a leftover transition notification —
        // not an intentional user focus switch — so suppress the dismissal.
        if sessionShowTime > 0,
           (ProcessInfo.processInfo.systemUptime - sessionShowTime) < PopupMetrics.focusSwitchGracePeriod { return }
        if !isRightClickInProgress {
            hide()
        }
    }

    @objc private func workspaceActiveSpaceDidChange() {
        hide()
    }

    // MARK: - Sub-Bar Presentation

    private func convertHoverFrameToScreen(_ hoverFrame: CGRect) -> NSRect {
        guard let panel, let contentView = panel.contentView else { return .zero }
        let viewRect = NSRect(x: hoverFrame.minX, y: hoverFrame.minY, width: hoverFrame.width, height: hoverFrame.height)
        let windowRect = contentView.convert(viewRect, to: nil)
        return panel.convertToScreen(windowRect)
    }

    // MARK: - Tooltip Presentation

    /// Presents a bar button's hover tooltip in the screen-space tooltip window. Converts the
    /// button frame from popupHoverSpace to screen coordinates and hands the expanded sub-bar's
    /// frame to the placer as an avoidance rect, so the tooltip flips below the bar instead of
    /// colliding with the sub-bar (or being clamped on top of the bar's own buttons, the old
    /// in-panel behavior).
    private func presentTooltip(text: String, localFrame: CGRect, effectiveTheme: String, isDark: Bool) {
        guard let panel, panel.isVisible else { return }
        let targetScreenFrame = convertHoverFrameToScreen(localFrame)
        guard !targetScreenFrame.isEmpty else { return }
        var avoidanceRects: [CGRect] = []
        if subBarController.isShowing {
            avoidanceRects.append(subBarController.panelFrame)
        }
        tooltipController.show(
            text: text,
            targetScreenFrame: targetScreenFrame,
            avoidanceRects: avoidanceRects,
            effectiveTheme: effectiveTheme,
            isDark: isDark,
            maxWidth: panel.frame.width - 32
        )
    }

    private func handleSubBarToggle(for action: any Action, index: Int, frame: CGRect) {
        if subBarController.isShowing, subBarController.activeState?.groupID == action.id {
            subBarController.hide()
            modeStore.isSubBarActive = false
            modeStore.activeSubGroupID = nil
            return
        }
        // Click and hover feel the same: both open transiently with immediate-neighbor tolerance
        showSubBar(for: action, index: index, frame: frame, isPinned: false)
    }

    private func handleSubBarDwell(for action: any Action, index: Int, frame: CGRect) {
        subBarController.startDwell { [weak self] in
            guard let self else { return }
            self.showSubBar(for: action, index: index, frame: frame, isPinned: false)
        }
    }

    private func showSubBar(for action: any Action, index: Int, frame: CGRect, isPinned: Bool) {
        guard let context = currentActionContext else { return }
        let resolver = SubActionResolver()
        let catalog = currentActions ?? ActionCoordinator.shared.resolveActions(for: context)
        let children = resolver.subActions(of: action, in: catalog)
        guard !children.isEmpty else {
            subBarController.hide()
            modeStore.isSubBarActive = false
            modeStore.activeSubGroupID = nil
            return
        }

        let buttonScreenFrame = convertHoverFrameToScreen(frame)
        modeStore.isSubBarActive = true
        modeStore.activeSubGroupID = action.id

        let scale = PopupMetrics.scaleMultiplier(for: settingsStore.get(SettingKey.popupScale))
        let rawTheme = settingsStore.get(SettingKey.popupTheme)
        let themeCategory = PopupThemeModel.category(fromStored: rawTheme)
        let appearance = settingsStore.get(SettingKey.popupThemeColor)
        let systemIsDark = NSApp.effectiveAppearance.name.rawValue.contains("Dark")
        let effectiveTheme = themeCategory == .glass ? "glass" : PopupThemeModel.classicToken(appearance: appearance, systemIsDark: systemIsDark)
        let effectiveColorScheme = PopupThemeModel.effectiveScheme(appearance: appearance, systemIsDark: systemIsDark)

        let mainBarAbove: Bool
        if let panel, let currentContext {
            mainBarAbove = PopupPositioner.isPlacedAbove(frame: panel.frame, releasePoint: currentContext.cursorPosition)
        } else {
            mainBarAbove = modeStore.searchResultsAbove
        }

        let actuallyAbove = subBarController.show(
            for: action,
            parentIndex: index,
            subActions: children,
            parentButtonScreenFrame: buttonScreenFrame,
            mainBarScreenFrame: panel?.frame,
            isPinned: isPinned,
            searchResultsAbove: modeStore.searchResultsAbove,
            mainBarAbove: mainBarAbove,
            effectiveTheme: effectiveTheme,
            effectiveColorScheme: effectiveColorScheme,
            scale: scale,
            context: context,
            presenter: ActionCustomizationManager.shared,
            onResult: { [weak self] result in
                self?.subBarController.hide()
                self?.modeStore.isSubBarActive = false
                self?.modeStore.activeSubGroupID = nil
                self?.deliverResult(result)
            },
            onRunAI: { [weak self] actionID in
                self?.usageStore.record(actionID)
                guard let self, let preset = AIServiceManager.shared.preset(forActionID: actionID) else { return }
                self.subBarController.hide()
                self.modeStore.isSubBarActive = false
                self.modeStore.activeSubGroupID = nil
                let prompt = AIServiceManager.shared.promptForPreset(preset)
                self.runAIPreset(prompt: prompt, title: preset.title)
            },
            onRunLoadingAction: { [weak self] action in
                guard let self, let context = self.currentActionContext else { return }
                self.subBarController.hide()
                self.modeStore.isSubBarActive = false
                self.modeStore.activeSubGroupID = nil
                self.runLoadingAction(action, with: context, isSecondaryClick: self.pendingClickIntent == .secondary)
            },
            onWillPerformAction: { [weak self] action in
                guard let self else { return }
                self.pendingDelivery = action.delivery
                self.pendingActionTitle = action.title
                self.pendingActionIcon = action.displayIcon(using: ActionCustomizationManager.shared)
                self.inFlightDeliveryContext = self.deliverySnapshot(for: action)
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .primary }
        )
        modeStore.subBarAbove = actuallyAbove
    }

    func runAIPreset(prompt: String, title: String) {
        guard let context = currentActionContext else {
            Log.ai.error("Cannot run AI preset: currentActionContext is nil")
            return
        }
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        let selection = context.selection
        let selectionText = selection.text
        let anchorFrame = panel?.frame ?? lastPopupFrame
        let targetCanPaste = PasteAvailability.effective(policy: selection.appPolicy, probe: modeStore.canPaste)

        hide()
        let session = aiSessionID

        toastController.showLoading(message: String(localized: "Generating…"), anchorFrame: anchorFrame) { [weak self] in
            self?.cancelActiveTasks()
        }

        let task = Task { @MainActor in
            self.modeStore.isProcessingAI = true
            defer {
                if !Task.isCancelled {
                    self.activeStreamingTask = nil
                    self.modeStore.isProcessingAI = false
                }
            }

            var hasYielded = false

            do {
                let provider = AIServiceManager.shared.currentProvider
                if provider.type == .browser {
                    _ = try await provider.process(prompt: prompt, text: selectionText)
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    self.toastController.hide()
                    self.deliverResult(.success)
                    return
                }

                var accumulated = ""

                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    accumulated += chunk
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        if !hasYielded {
                            hasYielded = true
                            self.toastController.hide()
                            let canPaste = targetCanPaste
                            guard !Task.isCancelled, session == self.aiSessionID else { return }
                            self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        }
                        self.showResultCard(text: cleaned, isError: false, title: title, isStreaming: true, session: session)
                    }
                }

                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                self.toastController.hide()
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        self.showResultCard(text: "No response generated", isError: true, title: title, isStreaming: false, session: session)
                    }
                } else {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                    }
                    self.showResultCard(text: finalResponse, isError: false, title: title, isStreaming: false, session: session)
                }
            } catch is CancellationError {
                Log.ai.info("AI streaming cancelled")
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                self.toastController.hide()
                Log.ai.error("AI preset execution failed: \(error.localizedDescription)")
                if !hasYielded {
                    let canPaste = targetCanPaste
                    guard !Task.isCancelled, session == self.aiSessionID else { return }
                    self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.showResultCard(text: message, isError: true, title: title, isStreaming: false, session: session)
            }
        }
        activeStreamingTask = task
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
        /// The action's declared delivery (secondary outcome + per-click toasts), snapshotted from
        /// the performing action right before the perform. `nil` means no declaration: the unified
        /// decision derives the secondary and default toasts exactly as before.
        let delivery: ActionDelivery?
        /// The target app the result will be delivered to. Captured synchronously with the other
        /// inputs: while the (non-activating) panel is up, the source app stays frontmost, and
        /// `exitKeyMode()` reactivates exactly this app on hide — so the snapshot is the same app
        /// `pasteProbe` must inspect, without reading frontmost state after hide or an await.
        let application: NSRunningApplication?
        /// The user's chosen behavior for this click (preview/paste/copy), resolved from the two
        /// General-tab settings at snapshot time.
        let preference: ResultDeliveryPreference
        /// The performing action's title — the result card header. nil for explicit user requests.
        let actionTitle: String?
        /// The performing action's display icon (customization-resolved) — the result card header
        /// icon. Captured alongside `actionTitle` by the same perform paths.
        let actionIcon: ActionIcon?
        /// The selection context captured before any early-close (loading actions), used to re-show
        /// the popup as a preview card. nil when the popup never closed.
        let selection: SelectionContext?
    }

    /// Snapshots the delivery inputs from the current session state. Called on the main actor,
    /// synchronously, before any dismissal or await, so the decision never depends on live state
    /// read after `hide()` or after the probe suspension.
    func deliverySnapshot(for action: (any Action)? = nil, clickIntent: ActionResultDelivery.ClickIntent? = nil) -> DeliveryContext {
        let intent = clickIntent ?? pendingClickIntent
        let actionDelivery = action?.delivery ?? pendingDelivery
        let title = action?.title ?? pendingActionTitle
        let icon = action?.displayIcon(using: ActionCustomizationManager.shared) ?? pendingActionIcon
        let targetApp = previousFrontmostApp ?? (frontmostApplicationProvider()?.bundleIdentifier != Bundle.main.bundleIdentifier ? frontmostApplicationProvider() : previousFrontmostApp)
        return DeliveryContext(
            policy: currentActionContext?.selection.appPolicy ?? .default,
            clickIntent: intent,
            delivery: actionDelivery,
            application: targetApp,
            preference: preference(for: intent),
            actionTitle: title,
            actionIcon: icon,
            selection: currentActionContext?.selection
        )
    }

    /// Checks if the target application is still the active frontmost application.
    /// If the user switched to a different application while an action was executing asynchronously,
    /// automated paste must not blindly post into the new foreground window.
    private func isTargetApplicationActive(_ targetApp: NSRunningApplication?) -> Bool {
        guard let targetApp else { return true }
        guard let frontmost = frontmostApplicationProvider() else { return true }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }
        return frontmost.processIdentifier == targetApp.processIdentifier
    }

    /// Routes a performed result into the tree-walk, snapshotting the delivery inputs first.
    /// Decision 8: dismissal is decided once on the top-level result; the tree-walk never hides
    /// per-item. `hide()` runs before `handleActionResult` so `exitKeyMode()` reactivates the target
    /// source app before any synthetic keyboard events (.paste, .cut, etc.) are posted — and the
    /// delivery snapshot is taken before that `hide()` clears the live context. The declared
    /// delivery is single-use per perform: the snapshot is its only consumer, so it is cleared
    /// immediately after — a later `onResult` paste (completion buttons route here directly) must
    /// never reuse a prior action's declaration. Internal for tests.
    func deliverResult(_ result: ActionResult, delivery: DeliveryContext? = nil) {
        let resolvedDelivery = delivery ?? inFlightDeliveryContext ?? deliverySnapshot()
        inFlightDeliveryContext = nil
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        if shouldDismiss(result, delivery: resolvedDelivery) {
            hide()
        }
        handleActionResult(result, delivery: resolvedDelivery, suppressDeliveryToast: result.containsToast)
    }

    /// Walks an ActionResult produced by a perform, rendering presentation results in the popup and
    /// routing leaf effects to the effect handler. Never hides the popup per-item — dismissal is
    /// decided once on the top-level result via `dismissesPopup`. `delivery` carries the captured
    /// paste-vs-copy inputs; `nil` means the result is an explicit user request never re-decided.
    /// `suppressDeliveryToast` is true when the top-level result contains a `.toast`: every effect's
    /// delivery companion toast is skipped so the script toast wins (one toast per run).
    func handleActionResult(_ result: ActionResult, delivery: DeliveryContext? = nil, suppressDeliveryToast: Bool = false) {
        switch result {
        case .toast(let feedback):
            presentToast(feedback)
        case .openConfiguration(let request):
            presentConfiguration(for: request)
        case .sequence(let items):
            for item in items { handleActionResult(item, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast) }
        default:
            handleEffect(result, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast)
        }
    }

    /// Routes a leaf effect to DefaultActionResultHandler and surfaces any thrown error uniformly
    /// (decision 9): an error becomes a dismissing `.toast(.error)`. Returns the task
    /// so a caller can await the posted effect.
    ///
    /// Applies the standardized paste-vs-copy delivery decision (`.paste` → `.copy` when the click
    /// was a force-copy, the app policy forbids paste, or the target app can't Paste). Only leaf
    /// text results routed here are re-decided; explicit user requests (the AI card's Paste/Copy
    /// buttons) pass through untouched via a nil `delivery`.
    @discardableResult
    private func handleEffect(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false) -> Task<Void, Never> {
        let effect = result
        return Task { @MainActor in
            do {
                let resolved = await resolveDelivery(effect, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast)
                if case .text(let text) = resolved.result {
                    // Preview preference: render the returned text in the native AI result card
                    // without delivering any effect. The popup stays open (a top-level `.text` never
                    // dismisses via dismissesPopup); Esc collapses via exitContent. Probe paste
                    // availability when it was never probed (production passes the trigger-site probe
                    // answer into show(for:pasteAvailable:); nil here means it was skipped) so the
                    // card gates its Paste button on the real answer — an unknown probe answer still
                    // normalizes to cannot-paste (safe default).
                    if modeStore.canPaste == nil {
                        modeStore.canPaste = await pasteProbe.canPaste(in: delivery?.application, policy: delivery?.policy ?? .default) ?? false
                    }
                    showResultCard(text: text, isError: false, title: delivery?.actionTitle ?? "Action", icon: delivery?.actionIcon, session: aiSessionID)
                    return
                }
                try await resultHandler.handle(resolved.result, in: panel?.contentView)
                if let toast = resolved.toast, !suppressDeliveryToast {
                    toastController.show(toast, anchorFrame: panel?.frame ?? lastPopupFrame)
                }
            } catch {
                handleActionResult(.toast(StatusFeedback(error: error)))
            }
        }
    }

    /// Decides how a text result should be delivered, per the standardized rule, and which
    /// companion toast (if any) surfaces. The click intent, app policy, and the action's declared
    /// delivery come from the snapshot, never from live state read after an await. A nil `delivery`
    /// (an explicit user request, e.g. the AI card's Paste/Copy buttons) passes the result through
    /// untouched with no toast. Only a `.paste` outcome can be downgraded to `.copy`, so the paste
    /// probe runs only when a paste outcome is actually on the table (the raw result is a paste, or
    /// a declared secondary is a paste); the declared secondary and per-click toasts still apply to
    /// any result.
    private func resolveDelivery(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false) async -> (result: ActionResult, toast: StatusFeedback?) {
        guard let delivery else { return (result, nil) }
        // A declared `.paste` secondary is pasted on a secondary click, so the probe must run for it
        // too; likewise a `.text` result whose user preference is paste. The force-copy short-circuit
        // below applies only when the click's outcome is a copy.
        let declaredSecondaryIsPaste = delivery.clickIntent == .secondary && isPaste(delivery.delivery?.secondary)
        let preference = delivery.preference
        let declaredSecondaryOverrides = delivery.clickIntent == .secondary && delivery.delivery?.secondary != nil
        let textPrefersPaste = isText(result) && preference == .paste && !declaredSecondaryOverrides
        let couldPaste = isPaste(result) || declaredSecondaryIsPaste || textPrefersPaste
        // The unified paste decision: per-app rules (assume/deny paste) answer definitively and
        // skip the AX walk entirely (no Accessibility dependency for those apps); a force-copy click
        // (a secondary click whose outcome is a copy — derived, or a non-paste declared secondary)
        // also skips it (the outcome is a copy regardless). A declared `.paste` secondary or a
        // `.text`+paste preference is the exception: the outcome is a paste, so the probe still runs.
        // Otherwise probe the target app and treat unknown availability as cannot-paste — the safe
        // default: never paste blindly when we cannot confirm the target supports it. The target is
        // the snapshotted app captured before hide(), never frontmost state read after suspension.
        let isTargetActive = isTargetApplicationActive(delivery.application)
        let canPaste: Bool
        if !couldPaste || !isTargetActive {
            canPaste = false // unused: `resolve` only consults it for a selected `.paste`, or target app inactive
        } else if (delivery.clickIntent == .secondary && !(declaredSecondaryIsPaste || textPrefersPaste)) || !PasteAvailability.needsProbe(policy: delivery.policy) {
            canPaste = PasteAvailability.effective(policy: delivery.policy, probe: nil) ?? false
        } else {
            canPaste = await pasteProbe.canPaste(in: delivery.application, policy: delivery.policy) ?? false
        }
        let resolved = ActionResultDelivery.resolve(
            raw: result,
            clickIntent: delivery.clickIntent,
            canPaste: canPaste,
            delivery: delivery.delivery ?? .none,
            preference: preference
        )
        return (resolved.result, suppressDeliveryToast ? nil : resolved.toast)
    }

    private func isPaste(_ result: ActionResult?) -> Bool {
        guard case .paste = result else { return false }
        return true
    }

    /// Resolves the user's chosen behavior for a click from the two General-tab settings. Unknown
    /// stored values fall back to the defaults (primary paste, secondary copy).
    private func preference(for clickIntent: ActionResultDelivery.ClickIntent) -> ResultDeliveryPreference {
        let key: SettingKey<String> = clickIntent == .primary ? .primaryClickBehavior : .secondaryClickBehavior
        return ResultDeliveryPreference(rawValue: settingsStore.get(key))
            ?? (clickIntent == .primary ? .paste : .copy)
    }

    private func isText(_ result: ActionResult) -> Bool {
        guard case .text = result else { return false }
        return true
    }

    /// Dismissal for a top-level result: the popup stays open exactly when the actual *resolved*
    /// outcome is `.text` (preview) and dismisses otherwise. Mirroring the resolver's Select step
    /// synchronously (before the delivery task runs) keeps dismissal consistent with the delivered
    /// outcome: a declared secondary beats the picker, so a `.text` raw result whose declared
    /// secondary dismisses still dismisses. `canPaste` is irrelevant here — every probe outcome
    /// (an honored paste or a downgraded copy) dismisses.
    private func shouldDismiss(_ result: ActionResult, delivery: DeliveryContext) -> Bool {
        let resolved = ActionResultDelivery.resolve(
            raw: result,
            clickIntent: delivery.clickIntent,
            canPaste: false,
            delivery: delivery.delivery ?? .none,
            preference: delivery.preference
        ).result
        if isText(resolved) { return false }
        return resolved.dismissesPopup
    }

    /// Runs a leaf action from a per-action global hotkey. Reuses the on-screen session when the
    /// popup is already up; otherwise opens on the retrieved selection so paste/preview still have
    /// a delivery context, then performs.
    func runBoundAction(_ action: any Action, with context: ActionContext, pasteAvailable: Bool? = nil) {
        if panel?.isVisible != true {
            show(for: context.selection, pasteAvailable: pasteAvailable)
        } else if let pasteAvailable {
            modeStore.canPaste = pasteAvailable
        }
        if ActionIdentity.isAIPreset(action) {
            guard let preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
            runAIPreset(prompt: AIServiceManager.shared.promptForPreset(preset), title: preset.title)
            return
        }
        runAction(action, with: context, isSecondaryClick: false)
    }

    /// Performs an action directly (the right-click path, which the bar's SwiftUI Button never
    /// fires) and routes its result through the standard dismissal + tree-walk, recording usage.
    /// Mirrors the left-click perform path in PopupView. The delivery context is built here from
    /// `isSecondaryClick`, so the decision never depends on live state read after the perform await.
    /// Internal for tests (mirrors `runLoadingAction`).
    func runAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        if action.chrome.showsLoading {
            runLoadingAction(action, with: context, isSecondaryClick: isSecondaryClick)
            return
        }
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // The declared delivery + title are snapshotted into the DeliveryContext below — this
        // perform path's only consumer. Unlike the bar/search path, no `onWillPerformAction`
        // precedes it, so `pendingDelivery`/`pendingActionTitle` must stay untouched: a later
        // `deliverResult` (e.g. a completion-paste from a preview card) must never reuse this
        // perform's declaration.
        let preference = preference(for: clickIntent)
        let targetApp = previousFrontmostApp ?? (frontmostApplicationProvider()?.bundleIdentifier != Bundle.main.bundleIdentifier ? frontmostApplicationProvider() : previousFrontmostApp)
        let delivery = DeliveryContext(
            policy: context.selection.appPolicy,
            clickIntent: clickIntent,
            delivery: action.delivery,
            application: targetApp,
            preference: preference,
            actionTitle: action.title,
            actionIcon: action.displayIcon(using: ActionCustomizationManager.shared),
            selection: context.selection
        )
        inFlightDeliveryContext = delivery
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            isSecondaryClick: isSecondaryClick,
            match: match
        )
        Task { @MainActor in
            do {
                let result: ActionResult
                if action.chrome.isInlineResult,
                   let inFlightTask = InlineResultEvaluator.shared.runningTask(for: action.id, sessionID: self.aiSessionID) {
                    if let text = await inFlightTask.value {
                        result = .text(text)
                    } else {
                        result = try await action.perform(performContext)
                    }
                } else if action.chrome.isInlineResult, let cached = self.modeStore.inlineResults[action.id] {
                    result = .text(cached)
                } else {
                    result = try await action.perform(performContext)
                }
                if self.shouldDismiss(result, delivery: delivery) {
                    self.hide()
                }
                self.handleActionResult(result, delivery: delivery, suppressDeliveryToast: result.containsToast)
                self.inFlightDeliveryContext = nil
            } catch {
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                self.handleActionResult(.toast(StatusFeedback(error: error)))
                self.inFlightDeliveryContext = nil
            }
        }
    }

    /// Performs a `showsLoading` action with early-close: the popup hides immediately, a spinner
    /// toast attaches to the popup's last frame, and the result settles the toast (swap to
    /// description, or fade when the result carries none). Mirrors runAction's delivery snapshot:
    /// captured before the early hide so paste-vs-copy still sees the pre-dismissal context.
    /// Internal for tests.
    func runLoadingAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // The declared delivery + title are snapshotted into the DeliveryContext below — this
        // perform path's only consumer. Unlike the bar/search path, no `onWillPerformAction`
        // precedes it, so `pendingDelivery`/`pendingActionTitle` must stay untouched: a later
        // `deliverResult` must never reuse this perform's declaration.
        let targetApp = previousFrontmostApp ?? (frontmostApplicationProvider()?.bundleIdentifier != Bundle.main.bundleIdentifier ? frontmostApplicationProvider() : previousFrontmostApp)
        let delivery = DeliveryContext(
            policy: context.selection.appPolicy,
            clickIntent: clickIntent,
            delivery: action.delivery,
            application: targetApp,
            preference: preference(for: clickIntent),
            actionTitle: action.title,
            actionIcon: action.displayIcon(using: ActionCustomizationManager.shared),
            selection: context.selection
        )
        inFlightDeliveryContext = delivery
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            isSecondaryClick: isSecondaryClick,
            match: match
        )
        // Capture before the early hide so the spinner attaches to where the popup actually was.
        let anchorFrame = panel?.frame ?? lastPopupFrame
        hide()
        let message = action.chrome.loadingMessage ?? String(localized: "Opening \(action.title)…")
        toastController.showLoading(message: message, anchorFrame: anchorFrame) { [weak self] in
            self?.cancelActiveTasks()
        }
        let runID = UUID()
        activeLoadingID = runID
        let loadingTask = Task { @MainActor in
            defer {
                if self.activeLoadingID == runID {
                    self.activeLoadingTask = nil
                    self.activeLoadingID = nil
                }
            }
            do {
                let result = try await action.perform(performContext)
                guard !Task.isCancelled else {
                    self.toastController.hide()
                    return
                }
                await self.settleLoadingResult(result, delivery: delivery, suppressDeliveryToast: result.containsToast)
            } catch is CancellationError {
                Log.presentation.info("Loading action cancelled (id \(action.id, privacy: .public))")
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled else {
                    self.toastController.hide()
                    return
                }
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                await self.settleLoadingResult(.toast(StatusFeedback(error: error)), delivery: delivery)
            }
        }
        activeLoadingTask = loadingTask
    }

    /// Resolves a loading action's result into the toast: `.toast` swaps to that status,
    /// a delivered result's companion toast (a paste→copy downgrade's "Copied", a declared per-click
    /// toast) swaps in, and everything else (`.success`, `.openURL`, honored paste, native copy)
    /// fades the spinner. When `suppressDeliveryToast` is true (the top-level result already carries
    /// a `.toast`), the delivery companion is skipped and whatever toast is showing is left alone —
    /// the script toast item in the tree presents itself, one toast per run.
    private func settleLoadingResult(_ result: ActionResult, delivery: DeliveryContext, suppressDeliveryToast: Bool = false) async {
        switch result {
        case .toast(var feedback):
            feedback.keepVisible = false
            toastController.show(feedback)
        case .openConfiguration(let request):
            toastController.hide()
            presentConfiguration(for: request)
        case .sequence(let items):
            for item in items { await settleLoadingResult(item, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast) }
        default:
            let effect = result
            do {
                let resolved = await resolveDelivery(effect, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast)
                if case .text(let text) = resolved.result {
                    // Preview preference on a loading action: the popup early-closed for the spinner,
                    // so hide the spinner and re-show the popup as a content-mode card, anchored to
                    // the original selection (captured before the early close). Re-probe so the card
                    // gates its Paste button on the real answer.
                    toastController.hide()
                    if let selection = delivery.selection {
                        let canPaste = await pasteProbe.canPaste(in: delivery.application, policy: delivery.policy) ?? false
                        show(for: selection, pasteAvailable: canPaste)
                        showResultCard(text: text, isError: false, title: delivery.actionTitle ?? "Action", icon: delivery.actionIcon, session: aiSessionID)
                    }
                    return
                }
                try await resultHandler.handle(resolved.result, in: panel?.contentView)
                if let toast = resolved.toast, !suppressDeliveryToast {
                    toastController.swapTo(toast)
                } else if !suppressDeliveryToast {
                    toastController.hide()
                }
            } catch {
                await settleLoadingResult(.toast(StatusFeedback(error: error)), delivery: delivery)
            }
        }
    }

    /// Surfaces a StatusFeedback as the floating toast (the single status renderer). When `point`
    /// is provided, the toast centers over that point (e.g. mouse cursor); otherwise it attaches
    /// to the popup panel's live (or last) frame.
    public func showToast(_ feedback: StatusFeedback, at point: CGPoint? = nil) {
        let anchor: NSRect?
        if let point {
            anchor = NSRect(origin: point, size: CGSize(width: 1, height: 1))
        } else {
            anchor = panel?.frame ?? lastPopupFrame
        }
        toastController.show(feedback, anchorFrame: anchor)
    }

    /// Surfaces a StatusFeedback as the floating toast (the single status renderer). The toast
    /// is independent of the popup, so it shows whether the popup stays up or has already hidden;
    /// it always attaches to the popup's live (or last) frame — never the pointer.
    private func presentToast(_ feedback: StatusFeedback) {
        showToast(feedback)
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
