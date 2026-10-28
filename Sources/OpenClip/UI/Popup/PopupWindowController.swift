// PopupWindowController.swift
// OpenClip
//
// Manages the popup panel's lifecycle, event tracking, placement, and animation.
// Modes: actions bar <-> search palette <-> result card. Search mode makes the panel key and restores
// focus to the previous app on exit. Content mode is also key, with Esc owned by the SwiftUI card.
// `cardIsModal` suppresses automatic dismissal until the user answers (Copy, Paste, or Esc).
// Result trees are walked by handleActionResult: presentation renders here, leaf effects route to
// DefaultActionResultHandler, and dismissal is decided once via ActionResult.dismissesPopup.
import AppKit
import SwiftUI
import Combine
import Core

@MainActor
public class PopupWindowController {
    var panel: PopupPanel?
    // Re-shows keep the AI session but invalidate pending Space recovery from an earlier presentation.
    private(set) var presentationAttemptID = UUID()
    private var didAttemptSpaceRecovery = false
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
    /// show(for:), reactivated on exitKeyMode/hide, cleared only by hide().
    var previousFrontmostApp: NSRunningApplication?

    /// Frame of the main bar prior to entering search mode, so exitSearch() can restore exact placement.
    private var preSearchFrame: NSRect?

    /// Opened directly into search (e.g. by shortcut): exitSearch() dismisses instead of falling back to the bar.
    public private(set) var openedDirectlyInSearch: Bool = false

    /// Session start time. `workspaceDidActivateApp` ignores activations within ~300 ms, when a clipboard manager's queued activation can arrive.
    var sessionShowTime: TimeInterval = 0

    private var hoveredAction: (any Action)?

    /// Last two pointer samples for sub-bar menu-aim. `previous` is the sample before `latest`.
    private var latestPointerLocation: CGPoint?
    private var previousPointerLocation: CGPoint?
    private var lastPointerMoveTime: TimeInterval?
    private var pendingGroupAim: PendingGroupAim?
    private var groupAimRestTask: Task<Void, Never>?

    private struct PendingGroupAim {
        let groupID: String
        let commit: @MainActor () -> Void
    }

    private struct AimSegment {
        var previous: CGPoint?
        var current: CGPoint
        var isNewMovement: Bool
    }

    private var isMenuTracking = false

    /// Tracks whether a right-click mouse-down originated within the popup bar.
    private var isRightClickInProgress = false

    /// Click intent of the latest bar/palette action (left vs right/⇧). Snapshotted into a `DeliveryContext` when the action performs.
    private var pendingClickIntent: ActionResultDelivery.ClickIntent = .primary

    /// Declared delivery of the latest bar/palette action. Set just before it runs; consumed once by the next `deliverResult`.
    var pendingDelivery: ActionDelivery? = nil

    /// Latest action's title for the card header. Same lifecycle as `pendingDelivery`.
    var pendingActionTitle: String? = nil

    /// Latest action's display icon for the card header. Same lifecycle as `pendingActionTitle`.
    var pendingActionIcon: ActionIcon? = nil

    /// Latest action's ID for delivery preference resolution. Same lifecycle as `pendingActionTitle`.
    var pendingActionID: String? = nil

    /// Latest action's recommended result. Same lifecycle as `pendingActionTitle`.
    var pendingActionRecommendedResult: ActionResultDeliveryMode? = nil

    /// Latest action's output kind. Same lifecycle as `pendingActionTitle`.
    var pendingActionOutputKind: ActionOutputKind? = nil

    /// Delivery context snapshotted before an action performs. Kept across hide() so async actions deliver with it.
    var inFlightDeliveryContext: DeliveryContext? = nil

    /// Frontmost-app provider; injectable for app-switching tests.
    var frontmostApplicationProvider: @MainActor () -> NSRunningApplication? = {
        NSWorkspace.shared.frontmostApplication
    }

    /// Paste-support probe; injectable for tests.
    private let pasteProbe: PasteAvailabilityProbing

    /// Toast surface for statuses and the paste→copy notice. Independent of the panel, so it shows after hide().
    let toastController: ToastPanelController
    private var captureToastPresentationID: UUID?
    private var isCaptureToastCurrent: Bool {
        guard let captureToastPresentationID else { return false }
        return toastController.presentationID == captureToastPresentationID
    }

    /// The standalone floating panel hosting group sub-actions and AI tool presets.
    public let subBarController: SubBarPanelController

    /// Screen-space tooltip surface shared with the sub-bar controller; sits above both bar panels to escape clipping.
    public let tooltipController: TooltipPanelController

    /// The resolved active actions for the current session, used for sub-action resolution.
    private var currentActions: [any Action]? = nil

    /// Last on-screen popup frame (screen coords), kept after hide() so toasts stay where the popup was.
    var lastPopupFrame: NSRect?

    /// Settings store for the per-click result-delivery preference.
    private let settingsStore: SettingsStore

    /// Session token for AI streaming, bumped by hide() and show(for:). Chunks from an abandoned stream are dropped on mismatch.
    public private(set) var aiSessionID = UUID()

    /// Live AI stream for the session, cancelled directly by hide() rather than via SwiftUI teardown, which can race AppKit's hide().
    var activeStreamingTask: Task<Void, Never>?
    private var activeAIPresetID: String?

    /// Active loading action task reference so clicking the loading toast can cancel in-flight execution.
    var activeLoadingTask: Task<Void, Never>?
    private var activeLoadingID: UUID?

    /// Suppresses distance-based auto-dismiss during the onboarding sandbox.
    public var isOnboardingVisible: Bool = false

    /// Trackpad scroll accumulator, so resting palms or finger-lift micro-scrolls don't dismiss.
    private var accumulatedScrollDelta: CGFloat = 0

    /// True while a detached interactive surface is open (`ActionResult.suspendsScrollDismissal`). Cleared when the session ends.
    private var isScrollDismissalSuspended = false
    private var distanceDismissGraceUntil: TimeInterval?

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
            self?.clearPendingGroupAim()
            self?.modeStore.isSubBarActive = false
            self?.modeStore.activeSubGroupID = nil
            self?.updateToastPlacement()
        }

        // Sub-bar tracking areas feed hover when event monitors can't see the pointer (e.g. over another app's fullscreen Space).
        self.subBarController.onTrackingMouseMoved = { [weak self] in self?.handleTrackingMouseMoved() }

        modeStore.$isSubBarActive.sink { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if self.modeStore.mode == .actions {
                panel.pinBottomEdgeOnResize = self.modeStore.searchResultsAbove
            }
        }.store(in: &cancellables)
    }

    /// Starts the paste-availability probe (rules first, then AX), run in parallel with selection retrieval. Not cached,
    /// since paste depends on focus context, unless a per-app rule answers definitively.
    public func preparePasteProbe(for app: NSRunningApplication?, policy: AppPolicyContext) -> Task<Bool?, Never> {
        Task { @MainActor in
            await pasteProbe.canPaste(in: app, policy: policy)
        }
    }

    public func show(for context: SelectionContext, pasteAvailable: Bool? = nil, initialMode: PopupMode = .actions, captureFeedback: StatusFeedback? = nil) {
        show(for: context, pasteAvailable: pasteAvailable, preservingSessionID: nil, streamingTask: nil, initialMode: initialMode, captureFeedback: captureFeedback)
    }

    func show(for context: SelectionContext, pasteAvailable: Bool?, preservingSessionID: UUID?, streamingTask: Task<Void, Never>?, initialMode: PopupMode = .actions, captureFeedback: StatusFeedback? = nil) {
        ActionSound.prepareIfEnabled()
        presentationAttemptID = UUID()
        didAttemptSpaceRecovery = false
        let attemptID = presentationAttemptID
        let evaluator = InlineResultEvaluator.shared
        let aiSession: UUID
        if let preservingSessionID {
            aiSession = preservingSessionID
            aiSessionID = preservingSessionID
            activeStreamingTask = streamingTask
        } else {
            // Cancel the previous session's stream and bump the token so late chunks are dropped.
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
            activeLoadingTask?.cancel()
            activeLoadingTask = nil
            evaluator.cancelSession(aiSessionID)
            aiSession = UUID()
            aiSessionID = aiSession
        }

        isMenuTracking = false
        let selectionContext = context.with(
            pasteTargetAvailable: PasteAvailability.effective(policy: context.appPolicy, probe: pasteAvailable)
        )
        currentContext = selectionContext
        if isCaptureToastCurrent { toastController.hide() }
        captureToastPresentationID = nil
        sessionShowTime = ProcessInfo.processInfo.systemUptime
        distanceDismissGraceUntil = context.source == .ocr
            ? sessionShowTime + PopupMetrics.ocrArrivalDismissalGrace
            : nil

        // Capture the source app once per session. Skip when OpenClip itself is frontmost: storing ourselves loses the real source app.
        captureFrontmostAppIfNeeded()

        let actionContext = ActionContext(selection: selectionContext, modifiers: [])
        currentActionContext = actionContext
        let availableActions = ActionCoordinator.shared.resolveActions(for: actionContext)

        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        // A fresh show is placed as-is; enterSearch() re-enables pinning for growth.
        panel.pinBottomEdgeOnResize = false
        panel.releasesBottomPinAfterGrowth = false
        panel.horizontalAnchor = .none
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        preSearchFrame = nil
        openedDirectlyInSearch = (initialMode == .search)
        isScrollDismissalSuspended = false

        let rawAlignment = settingsStore.get(SettingKey.popupAlignment)
        let alignment = PopupBarAlignment(rawValue: rawAlignment) ?? .left
        let rawVertical = settingsStore.get(SettingKey.popupVerticalPosition)
        let verticalPosition = PopupVerticalPosition(rawValue: rawVertical) ?? .auto

        // Card direction from the real screen position. A shortcut-opened palette anchors on the selection and honors the same placement prefs as the bar.
        let screen = PopupPositioner.screen(containing: context.cursorPosition) ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
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
        // Probed before this frame so Paste/Cut are gated on the first render; nil keeps them visible.
        modeStore.canPaste = pasteAvailable

        let activeActions = pasteAvailable == false
            ? availableActions.filter { !($0 is any PasteRequiringAction) }
            : availableActions
        self.currentActions = activeActions

        modeStore.inlineResults.removeAll()
        let catalog = ActionCoordinator.shared.searchCatalog(for: actionContext)
        var combinedActions = activeActions
        for item in catalog where !combinedActions.contains(where: { $0.id == item.id }) {
            combinedActions.append(item)
        }
        let inlineActions = combinedActions.filter { $0.chrome.isInlineResult }
        let textHash = context.text.hashValue

        for action in inlineActions {
            if let prewarmed = evaluator.prewarmedResult(for: action, textHash: textHash) {
                modeStore.inlineResults[action.id] = prewarmed
            } else if let syncResult = evaluator.evaluateSynchronous(action: action, context: actionContext) {
                modeStore.inlineResults[action.id] = syncResult
            } else {
                evaluator.startEvaluation(action: action, context: actionContext, sessionID: aiSession) { [weak self] result in
                    guard let self, let result, !result.isEmpty else { return }
                    guard self.aiSessionID == aiSession else { return }
                    self.modeStore.inlineResults[action.id] = result
                }
            }
        }

        let rootView = PopupView(
            settingsStore: settingsStore,
            actions: activeActions,
            allActions: activeActions,
            context: actionContext,
            alternateSearchContext: alternateClipboardSearchContext(for: context),
            onSearchContextChanged: { [weak self] selection in
                self?.updateSearchContext(selection)
            },
            screenWidth: screenBounds.width,
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
            onPinCard: { [weak self] in self?.pinCard() },
            onCardEffect: { [weak self] result in
                self?.performCardEffect(result)
            },
            onResult: { [weak self] result in
                self?.deliverResult(result)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
                self?.keepPanelOnScreen()
                self?.updateToastPlacement()
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
            onWillPerformAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext,
                      self.canPerformAction(action, in: context) else { return false }
                self.pendingDelivery = action.delivery
                self.pendingActionTitle = action.title
                self.pendingActionIcon = action.displayIcon(using: ActionCustomizationManager.shared)
                self.pendingActionID = action.id
                self.pendingActionRecommendedResult = action.chrome.recommendedResult
                self.pendingActionOutputKind = action.chrome.outputKind
                self.inFlightDeliveryContext = self.deliverySnapshot(for: action, clickIntent: clickIntent)
                return true
            },
            onRunLoadingAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext else { return }
                self.runLoadingAction(action, with: context, isSecondaryClick: clickIntent == .secondary)
            },
            onRunAI: { [weak self] actionID in
                guard let self, let preset = AIServiceManager.shared.preset(forActionID: actionID) else { return }
                let prompt = AIServiceManager.shared.promptForPreset(preset)
                self.runAIPreset(prompt: prompt, title: preset.title, presetID: preset.id)
            },
            onRunAIPrompt: { [weak self] instruction, replace, includeContext in
                self?.runAIPrompt(instruction, replace: replace, includeContext: includeContext)
            },
            onSaveAIPrompt: { [weak self] instruction, replace in
                self?.saveAndRunAIPrompt(instruction, replace: replace)
            },
            onFollowUp: { [weak self] instruction in
                self?.runFollowUp(instruction)
            },
            onCancelFollowUp: { [weak self] in
                self?.cancelFollowUp()
            },
            onStepVersion: { [weak self] delta in
                self?.stepVersion(delta)
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .primary },
            onShowTooltip: { [weak self] text, localFrame, theme, isDark in
                self?.presentTooltip(text: text, localFrame: localFrame, effectiveTheme: theme, isDark: isDark)
            },
            onHideTooltip: { [weak self] in
                self?.tooltipController.hide()
            }
        )
        syncPanelAppearance(panel)
        let hosting = PopupPanel.ContentView(rootView: rootView)
        hosting.onMouseMoved = { [weak self] in self?.handleTrackingMouseMoved() }
        panel.contentView = hosting
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)

        // Card direction from the real screen position and the rendered panel size.
        let calculatedFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: size, in: screenBounds, alignment: alignment, verticalPosition: verticalPosition)
        positionPanel(panel, size: size, for: context, alignment: alignment, verticalPosition: verticalPosition)
        cardAbove = calculatedFrame.minY < screenBounds.minY + PopupMetrics.cardAboveThreshold
        modeStore.searchResultsAbove = cardAbove
        modeStore.subBarAbove = PopupPositioner.isPlacedAbove(frame: calculatedFrame, releasePoint: context.cursorPosition)
        lastPopupFrame = panel.frame
        // Placement is fixed; content-driven width changes must re-center rather than drift off the cursor.
        panel.horizontalAnchor = .center
        // Content-driven growth keeps the bottom edge fixed when the popup sits low. A directly opened palette is not pinned, so its top edge stays fixed.
        panel.pinBottomEdgeOnResize = initialMode == .search ? false : cardAbove
        if context.source == .ocr, let captureFeedback {
            toastController.show(captureFeedback, anchorFrame: panel.frame, placement: .nearCursor(context.cursorPosition))
            captureToastPresentationID = toastController.presentationID
            updateToastPlacement()
        }
        if NSClassFromString("XCTestCase") == nil {
            panel.orderFront(nil)
        }
        
        setupMonitors()
        // Two bounded snapshots catch delayed AppKit hiding/Space changes without polling.
        Task { @MainActor [weak self] in
            for delay in [150_000_000, 600_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                guard let self, self.presentationAttemptID == attemptID, self.currentContext != nil else { return }
                if delay == 150_000_000 {
                    self.recoverPopupSpaceIfNeeded(for: attemptID,
                        frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
                } else if self.panel?.isOnActiveSpace == false {
                    self.logPresentation("space-recovery-unresolved")
                } else if self.didAttemptSpaceRecovery {
                    self.logPresentation("space-recovery-verified")
                }
            }
        }

        if initialMode == .search {
            enterKeyMode()
            Task { @MainActor in
                await Task.yield()
                self.focusSearchField()
            }
            scheduleKeepPanelOnScreen()
        }
    }

    /// Replace stale WindowServer membership once after AppKit has had time to order the window.
    /// Never activate the app or make the panel key to recover an automatic action bar.
    @discardableResult
    func recoverPopupSpaceIfNeeded(for attemptID: UUID, frontmostPID: pid_t?,
                                   makePanel: () -> PopupPanel = { PopupPanel() }) -> Bool {
        guard presentationAttemptID == attemptID, !didAttemptSpaceRecovery,
              let context = currentContext, let panel,
              panel.isVisible, !panel.isOnActiveSpace, !panel.isKeyWindow, modeStore.mode == .actions,
              let sourcePID = context.sourceApp.processIdentifier,
              frontmostPID == sourcePID else { return false }
        didAttemptSpaceRecovery = true
        logPresentation("space-recovery-start")
        // Reordering the same window failed in live traces; keep the hosting view but give WindowServer a new window identity.
        let frame = panel.frame
        let content = panel.contentView
        let replacement = makePanel()
        replacement.heightCap = panel.heightCap
        replacement.appearance = panel.appearance
        replacement.ignoresMouseEvents = panel.ignoresMouseEvents
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = replacement
        replacement.contentView = content
        replacement.setFrame(frame, display: false)
        replacement.pinBottomEdgeOnResize = panel.pinBottomEdgeOnResize
        replacement.releasesBottomPinAfterGrowth = panel.releasesBottomPinAfterGrowth
        replacement.horizontalAnchor = panel.horizontalAnchor
        NotificationCenter.default.addObserver(self, selector: #selector(panelOcclusionDidChange(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: replacement)
        replacement.orderFront(nil)
        lastPopupFrame = replacement.frame
        logPresentation("space-recovery-recreated")
        return true
    }

    /// Metadata only: never include selected text, window titles, or clipboard contents.
    private func logPresentation(_ event: String) {
        guard let context = currentContext else { return }
        // Successful reads already have a cascade summary; log window metadata only for placement failures.
        guard event.hasPrefix("space-recovery") || didAttemptSpaceRecovery
            || (panel?.isVisible == true && panel?.isOnActiveSpace == false) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frame = panel.map { NSStringFromRect($0.frame) } ?? "none"
        let ageMS = sessionShowTime > 0 ? Int((ProcessInfo.processInfo.systemUptime - sessionShowTime) * 1000) : 0
        let metadata = "event=\(event) pid=\(ProcessInfo.processInfo.processIdentifier) source=\(context.sourceApp.bundleIdentifier ?? "unknown") frontmost=\(frontmost?.bundleIdentifier ?? "unknown") session=\(aiSessionID) ageMS=\(ageMS) visible=\(panel?.isVisible ?? false) activeSpace=\(panel?.isOnActiveSpace ?? false) unoccluded=\(panel?.occlusionState.contains(.visible) ?? false) appActive=\(NSApp.isActive) appHidden=\(NSApp.isHidden) window=\(panel?.windowNumber ?? -1) level=\(panel?.level.rawValue ?? 0) alpha=\(panel?.alphaValue ?? 0) key=\(panel?.isKeyWindow ?? false) hidesOnDeactivate=\(panel?.hidesOnDeactivate ?? false) frame=\(frame) mode=\(modeStore.mode)"
        let message: Core.LogMessage = "[Trace#\(context.traceID ?? 0, privacy: .public)] popup \(metadata, privacy: .public)"
        if event == "space-recovery-unresolved" {
            Log.presentation.warning(message)
        } else if event.hasPrefix("space-recovery") {
            Log.presentation.notice(message)
        } else {
            Log.presentation.debug(message)
        }
    }

    @objc private func panelOcclusionDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        logPresentation("occlusion-changed")
    }

    public var isVisible: Bool { (panel?.isVisible == true) || (currentContext != nil) }

    /// Starts a session without creating AppKit window monitors or ordering windows on screen.
    func startTestSession(for context: SelectionContext, pasteAvailable: Bool? = nil, initialMode: PopupMode = .actions) {
        presentationAttemptID = UUID()
        didAttemptSpaceRecovery = false
        isMenuTracking = false
        let selectionContext = context.with(
            pasteTargetAvailable: PasteAvailability.effective(policy: context.appPolicy, probe: pasteAvailable)
        )
        currentContext = selectionContext
        captureFrontmostAppIfNeeded()
        let actionContext = ActionContext(selection: selectionContext, modifiers: [])
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

    /// Records the frontmost app before the panel becomes key. Captures once per session (hide() clears it), never OpenClip itself.
    private func captureFrontmostAppIfNeeded() {
        guard previousFrontmostApp == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousFrontmostApp = app
    }

    /// Makes the panel key (a scoped exception to the never-key rule) without activating OpenClip, so the source app stays active.
    private func enterKeyMode() {
        guard let panel else { return }
        captureFrontmostAppIfNeeded()
        panel.allowsKey = true
        if NSClassFromString("XCTestCase") == nil {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Restores the never-key invariant and returns focus to the source app. Does not clear it: only hide() ends the session.
    private func exitKeyMode() {
        panel?.allowsKey = false
        if NSApp.isActive {
            previousFrontmostApp?.activate(options: [.activateAllWindows])
        }
    }

    /// Enters search mode, optionally scoped to a parent action's sub-actions. The panel becomes key without activating OpenClip.
    public func enterSearch(with scope: SearchScope? = nil, buttonLocalFrame: CGRect? = nil) {
        guard let panel, panel.isVisible else { return }
        // Fresh palette: drop the intent of the click that opened it, so a keyboard run isn't delivered as secondary.
        pendingClickIntent = .primary
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
            // Fresh entry, not a scope hop: the palette may be taller than the bar cap.
            modeStore.isSurfaceUserSized = false
            panel.heightCap = screenBounds(for: panel).height
            // Entry growth keeps the bottom edge fixed when low on screen (see PopupPanel.setFrame). That pin is one-shot;
            // later height changes anchor the top edge. Scope hops leave anchoring alone.
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
        // Make the search field first responder on the next run-loop turn; a @FocusState request during the mode change can be dropped.
        Task { @MainActor in
            await Task.yield()
            self.focusSearchField()
        }
        scheduleKeepPanelOnScreen()
    }

    /// The panel width for the palette: the default column plus the shadow ring on both sides.
    private var currentSearchPanelWidth: CGFloat {
        PopupMetrics.searchPanelWidth
    }

    private func alternateClipboardSearchContext(for selection: SelectionContext) -> SelectionContext? {
        guard !selection.isClipboardFallback,
              !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              TextSanitizer.isSubstantial(text),
              text.utf8.count <= Constants.maxTextLength,
              text != selection.text else { return nil }
        return SelectionContext(
            text: text,
            sourceApp: selection.sourceApp,
            cursorPosition: selection.cursorPosition,
            mouseDownLocation: selection.mouseDownLocation,
            selectionBounds: nil,
            timestamp: selection.timestamp,
            appPolicy: selection.appPolicy,
            isClipboardFallback: true,
            html: pasteboard.string(forType: .html),
            rtf: pasteboard.string(forType: .rtf),
            isEditable: false,
            pasteTargetAvailable: selection.pasteTargetAvailable
        )
    }

    private func updateSearchContext(_ selection: SelectionContext) {
        guard modeStore.mode == .search else { return }
        currentActionContext = ActionContext(
            selection: selection,
            modifiers: currentActionContext?.modifiers ?? []
        )
        // Inline values were for the original selection; clear them so the palette can't show a stale preview.
        modeStore.inlineResults.removeAll()
    }

    /// The hosting view grows the panel after the run-loop turn; nudge it back on screen once that growth lands (two retries, as in showResultCard).
    private func scheduleKeepPanelOnScreen() {
        DispatchQueue.main.async { [weak self] in self?.keepPanelOnScreen() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.keepPanelOnScreen() }
    }

    /// Opens the palette scoped to a bar row's sub-actions, resolved here via `SubActionProviding` so the view never touches the catalog.
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

    /// Leaves search mode for the actions bar. Hides only if the session opened directly in search. The bottom-edge pin stays
    /// active through the shrink so the bar returns to the field's spot; hide() and show(for:) clear it.
    public func exitSearch() {
        guard modeStore.mode == .search else { return }
        if openedDirectlyInSearch {
            hide()
            return
        }
        if let currentContext {
            currentActionContext = ActionContext(
                selection: currentContext,
                modifiers: currentActionContext?.modifiers ?? []
            )
        }
        modeStore.scope = nil
        modeStore.mode = .actions
        PaletteRowShortcuts.setActive(false)
        // Set explicitly so the bar keeps field anchoring for hover and banner growth.
        panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
        panel?.releasesBottomPinAfterGrowth = false
        if let preSearchFrame, let panel {
            panel.horizontalAnchor = .none
            // Collapse keeps the bottom edge (results above) or top edge (results below). Restore the bar's original bottom first.
            let restoredY = modeStore.searchResultsAbove ? preSearchFrame.minY : panel.frame.minY
            panel.setFrame(CGRect(x: preSearchFrame.origin.x, y: restoredY, width: preSearchFrame.width, height: panel.frame.height), display: false)
            panel.horizontalAnchor = .center
        }
        preSearchFrame = nil
        modeStore.isSurfaceUserSized = false
        resizeAnchor = nil
        panel?.heightCap = PopupMetrics.popupMaxHeight
        exitKeyMode() // reactivates previousFrontmostApp but keeps it for the session
    }

    // MARK: - AI Result Card

    /// True while the card is on screen and the user has dragged it aside (pinning it open). Un-dragged cards dismiss on outside clicks.
    public var cardIsModal: Bool { modeStore.mode == .content && hasUserMovedCard }
    public private(set) var hasUserMovedCard: Bool = false

    /// Applies a streaming "processing" flag only for its own session, so a stale stream can't re-stick isProcessingAI.
    func setAIProcessing(_ active: Bool, session: UUID) {
        guard session == aiSessionID else { return }
        modeStore.isProcessingAI = active
    }

    /// Shows an action's text (or error) in the result card and makes the panel key so Esc can collapse it. Paste and Copy are
    /// explicit requests and skip the paste-vs-copy re-decision. Chunks from abandoned streams are dropped.
    func showResultCard(
        text: String,
        isError: Bool,
        title: String,
        icon: ActionIcon? = nil,
        isStreaming: Bool = false,
        session: UUID,
        originalText: String? = nil,
        overrideOriginal: Bool = false,
        canFollowUp: Bool = true,
        file: FileOutputPayload? = nil
    ) {
        guard session == aiSessionID else { return }
        let showsVersions = canFollowUp && !isError && !isStreaming && file == nil
        let versionCount = showsVersions ? (cardConversation.map { $0.steps.count + redoSteps.count } ?? 1) : 1
        let versionIndex = showsVersions ? (cardConversation?.steps.count ?? 1) : 1
        if toastController.isLoading {
            toastController.hide()
        }
        modeStore.isProcessingAI = isStreaming
        let original = overrideOriginal ? originalText : currentActionContext?.selection.text
        // The selection the action ran on rides along so the card can diff input → output.
        modeStore.resultCard = ResultCardPayload(
            text: text,
            isError: isError,
            title: title,
            icon: icon,
            isStreaming: isStreaming,
            original: original,
            canFollowUp: canFollowUp,
            file: file,
            versionIndex: versionIndex,
            versionCount: versionCount
        )
        if !isStreaming {
            // A settled card hands keyboard focus to its instruction field.
            Task { @MainActor in
                await Task.yield()
                self.focusCardField()
            }
        }
        if modeStore.mode != .content {
            hasUserMovedCard = false
            PaletteRowShortcuts.setActive(false)
            panel?.pinBottomEdgeOnResize = modeStore.searchResultsAbove
            panel?.horizontalAnchor = .center
            // A remembered card may exceed the bar cap; let the panel grow to the screen.
            if let panel { panel.heightCap = screenBounds(for: panel).height }
            if isStreaming {
                // Lock dimensions on the first chunk so streaming doesn't resize the panel.
                modeStore.resultCardSize = rememberedSize(for: .card) ?? CGSize(
                    width: PopupMetrics.aiCardIdealWidth,
                    height: PopupMetrics.aiCardMinHeight
                )
                modeStore.isSurfaceUserSized = true
            } else {
                modeStore.resultCardSize = rememberedSize(for: .card)
                modeStore.isSurfaceUserSized = false
            }
            modeStore.mode = .content
            enterKeyMode()
        }

        // Nudge the hosting view to re-measure; NSHostingView won't re-measure on its own.
        fitPanelToContent()
        // Retry after the display cycle (DispatchQueue.main.async, not Task.yield, which doesn't guarantee a display pass).
        DispatchQueue.main.async { [weak self] in
            self?.fitPanelToContent()
        }
        // Safety-net retry: SwiftUI swaps the whole view tree on first content-mode entry.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.modeStore.mode == .content else { return }
            self.fitPanelToContent()
        }
    }

    /// Re-measures the hosting view, resizes the panel to its content, and nudges it back on screen.
    private func fitPanelToContent() {
        guard let contentView = panel?.contentView else { return }
        contentView.invalidateIntrinsicContentSize()
        contentView.layoutSubtreeIfNeeded()
        resizePanel(to: sanitizedPopupSize(contentView.fittingSize))
        keepPanelOnScreen()
    }

    /// Minimally moves an auto-placed resizable surface back on screen. User-dragged cards are left alone.
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

    /// The resizable popup surface (the result card). The search palette is content-sized and not resizable.
    private enum ResizableSurface {
        case card

        var minSize: CGSize {
            CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight)
        }

        var widthKey: SettingKey<Double> { SettingKey.resultCardWidth }

        var heightKey: SettingKey<Double> { SettingKey.resultCardHeight }
    }

    /// The resizable surface on screen, if any (only the result card).
    private var resizableSurface: ResizableSurface? {
        switch modeStore.mode {
        case .content: return .card
        case .search, .actions: return nil
        }
    }

    private func liveSize(for surface: ResizableSurface) -> CGSize? {
        switch surface {
        case .card: return modeStore.resultCardSize
        }
    }

    private func setLiveSize(_ size: CGSize?, for surface: ResizableSurface) {
        switch surface {
        case .card: modeStore.resultCardSize = size
        }
    }

    /// Last user size for `surface`, fitted to `screenBounds`; nil until resized, so default sizing applies.
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

    /// Panel and cursor position at drag start; nil when no drag is in flight.
    private var cardDragAnchor: (mouse: CGPoint, origin: CGPoint)?

    /// Moves the panel with the cursor, computed from the absolute cursor position against the `.began` anchor. A translation-based
    /// move would fight the moving window and crawl.
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
            if modeStore.mode == .search, let anchor = cardDragAnchor, var frame = preSearchFrame {
                frame.origin.x += panel.frame.origin.x - anchor.origin.x
                frame.origin.y += panel.frame.origin.y - anchor.origin.y
                preSearchFrame = frame
            }
            cardDragAnchor = nil
            panel.endUserDrag()
            if modeStore.mode == .content {
                hasUserMovedCard = true
            }
        }
    }

    /// Toggles the card's pin. Pinning makes it modal (same gate as dragging), suppressing auto-dismiss.
    func pinCard() {
        let nowPinned = !modeStore.isCardPinned
        modeStore.isCardPinned = nowPinned
        hasUserMovedCard = nowPinned
    }

    // MARK: - Resize

    /// Cursor, size, and surface captured at resize start; nil when no resize is in flight.
    private var resizeAnchor: (mouse: CGPoint, size: CGSize, surface: ResizableSurface)?

    /// Resizes the card from its handle, like `handleCardDrag`: absolute cursor position against the `.began` anchor, top-left fixed,
    /// clamped to the surface minimum and the screen. `.ended` remembers the size.
    func handleResize(_ edge: PopupResizeEdge, phase: ResultCardDragPhase, mouseLocation: CGPoint? = nil) {
        guard let panel, let surface = resizableSurface else { return }
        let mouse = mouseLocation ?? NSEvent.mouseLocation
        switch phase {
        case .began:
            // Same panel state as a move: no click-through mid-drag, and no re-centering or bottom pinning that would fight the top-left frames.
            panel.prepareForUserDrag()
            panel.pinBottomEdgeOnResize = false
            panel.releasesBottomPinAfterGrowth = false
            // Start from the on-screen size so the handle stays under the pointer; the dragged size is then used verbatim.
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
            // The dragged size persists until the surface closes (`isSurfaceUserSized`).
            if let size = liveSize(for: surface) {
                settingsStore.set(surface.widthKey, value: Double(size.width))
                settingsStore.set(surface.heightKey, value: Double(size.height))
            }
        }
    }

    /// On-screen surface size: the panel frame minus the shadow ring. Default sizes are never reported, so this is where the first resize starts.
    private func currentSurfaceSize(in panel: PopupPanel) -> CGSize {
        let ring = 2 * PopupMetrics.popupShadowInset
        return CGSize(width: panel.frame.width - ring, height: panel.frame.height - ring)
    }

    /// Applies a size: the panel is the surface plus its shadow ring, with the top-left corner fixed.
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
        if refiningPrevious != nil {
            // Leaving the card drops a follow-up in flight; the stream must not re-open it.
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
            refiningPrevious = nil
            modeStore.isProcessingAI = false
        }
        cardConversation = nil
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        modeStore.isCardPinned = false
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

    /// Runs an explicit card button (Paste/Copy) with no delivery context. Dismissing results hide the popup first, so exitKeyMode() reactivates the target app.
    private func performCardEffect(_ result: ActionResult) {
        if result.dismissesPopup {
            hide()
            handleActionResult(result, delivery: nil)
        } else {
            _ = handleEffect(result, delivery: nil)
        }
    }

    // MARK: - Panel Resize

    /// Resizes the panel to its content, anchored like `PopupPanel.setFrame`: a resize drag keeps the top-left; otherwise the
    /// bottom-edge pin decides. Screen and height clamping live in `PopupPanel.setFrame`.
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
        updateToastPlacement()
    }

    private func syncPanelAppearance(_ targetPanel: NSPanel) {
        let appearanceToken = settingsStore.get(SettingKey.popupThemeColor)
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isDark = PopupThemeModel.effectiveScheme(appearance: appearanceToken, systemIsDark: systemIsDark) == .dark
        targetPanel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
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

    public func hide(reason: String = #function, callerLine: Int = #line) {
        presentationAttemptID = UUID()
        logPresentation("hide reason=\(reason) callerLine=\(callerLine)")
        // End the AI session first: cancel the stream and invalidate its token so in-flight chunks are dropped.
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeLoadingTask?.cancel()
        activeLoadingTask = nil
        activeLoadingID = nil
        // Cancel in-flight work but keep warm inline-result caches for the next selection.
        InlineResultEvaluator.shared.endSession(aiSessionID)
        aiSessionID = UUID()
        refiningPrevious = nil
        cardConversation = nil

        if toastController.currentFeedback?.keepVisible == true || toastController.isLoading
            || isCaptureToastCurrent {
            toastController.hide()
        }
        captureToastPresentationID = nil
        subBarController.hide()
        tooltipController.hide()
        currentActions = nil
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        modeStore.canPaste = nil
        modeStore.inlineResults.removeAll()
        // Clear click intent so a stale intent or declared delivery can't leak into the next session.
        pendingClickIntent = .primary
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        pendingActionID = nil
        pendingActionRecommendedResult = nil
        pendingActionOutputKind = nil
        accumulatedScrollDelta = 0
        isScrollDismissalSuspended = false
        distanceDismissGraceUntil = nil
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
        modeStore.isCardPinned = false
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
        latestPointerLocation = nil
        previousPointerLocation = nil
        lastPointerMoveTime = nil
        clearPendingGroupAim()
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(panelOcclusionDidChange(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
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

    /// Runs the palette row a global ⌘-digit hotkey points at (1-based); false if there is no such row.
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
            trackPointerForGroupAim(at: cursorLoc)
            // Distance dismissal is suspended in search mode, while the card is modal, while AI processes, and during onboarding.
            let inArrivalGrace = PopupDismissalGrace.isActive(
                now: ProcessInfo.processInfo.systemUptime,
                deadline: distanceDismissGraceUntil
            )
            let distanceDismissActive = modeStore.mode != .search && modeStore.mode != .content
                && !modeStore.isProcessingAI && !isOnboardingVisible && !inArrivalGrace
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
                    hide(reason: "cursor-distance")
                }
            }
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            // Content test, not frame test: clicks in the shadow ring count as outside clicks.
            let inMain = isOverPanelContent(clickLoc)
            let inSub = subBarController.isShowing && subBarController.isOverContent(clickLoc)
            // Capture ⇧ at click time: the button runs on mouse-up and must deliver a copy when ⇧ is held.
            let isShift = event.modifierFlags.contains(.shift)
            pendingClickIntent = isShift ? .secondary : .primary
            if !inMain && !inSub && !cardIsModal {
                // A mouse-down within 100 ms of showing is likely part of the gesture that selected the text (e.g. triple-click).
                if sessionShowTime > 0,
                   (ProcessInfo.processInfo.systemUptime - sessionShowTime) < 0.1 {
                    break
                }
                hide()
            }
        case .rightMouseDown:
            // Right-click down prepares force-copy intent; execution waits for rightMouseUp, like a button.
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
            // Search scrolls the results list; the modal card scrolls its own content and never dismisses.
            if modeStore.mode == .search || modeStore.mode == .content { break }
            // A detached surface (e.g. Look Up) scrolls its own content and must not dismiss its popup.
            if isScrollDismissalSuspended { break }
            // Ignore the phantom scrollWheel a trackpad right-click emits before rightMouseDown, so it isn't dismissed.
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
            // Actions mode: any key dismisses, and keys land in the source app. Search: the field handles keys and Escape.
            // Content: Esc belongs to the SwiftUI card (.onKeyPress), so the monitor only observes.
            if modeStore.mode == .search { break }
            if modeStore.mode == .content {
                // Esc belongs to the SwiftUI card while the panel is key (handling it here would double-fire). If the panel lost key
                // (the card was clicked into another app), the monitor must answer Esc itself.
                if event.keyCode == 53, panel?.isKeyWindow != true {
                    hide()
                }
                return
            }
            // Escape closes an open sub-bar first; the next Escape dismisses the popup.
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

    /// Whether a screen point is over the popup's interactive content (panel minus the shadow ring). Ring clicks count as outside
    /// clicks, not bar clicks; a panel frame check would swallow them. Internal so tests can pin this contract.
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

    func updatePopupHover(at screenLocation: CGPoint, toggleClickThrough: Bool = true) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else {
            PopupHoverState.shared.location = nil
            return
        }

        // Click-through over the shadow ring lets clicks reach the app below. Only with global monitoring: otherwise
        // nothing notices re-entry and the panel would stay inert. The tracking-area path passes `toggleClickThrough: false`.
        let overContent = isOverPanelContent(screenLocation)
        if toggleClickThrough, PopupHoverState.shared.usesGlobalMouseMonitoring, !panel.isUserDragging {
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
        // Skip identical locations: @Published emits on every assignment, so hit-tests would rerun at event-monitor rate.
        guard point != PopupHoverState.shared.location else { return }
        PopupHoverState.shared.location = point
    }

    func updateSubBarHover(at screenLocation: CGPoint, toggleClickThrough: Bool = true) {
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
        if toggleClickThrough, SubBarHoverState.shared.usesGlobalMouseMonitoring {
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

    /// Feeds hover from the `.activeAlways` tracking areas, keeping hover, tooltips, and sub-bars alive while OpenClip is inactive
    /// (e.g. over another app's fullscreen Space). Recomputed from the live cursor, since relayout can emit spurious exits.
    /// Skips click-through: with no monitor, ignoring events would strand the panel.
    func handleTrackingMouseMoved() {
        let cursorLoc = NSEvent.mouseLocation
        updatePopupHover(at: cursorLoc, toggleClickThrough: false)
        updateSubBarHover(at: cursorLoc, toggleClickThrough: false)
        trackPointerForGroupAim(at: cursorLoc)
    }

    private func handleCancelSubBarDwell() {
        clearPendingGroupAim()
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
        // A right-click resigns active before rightMouseUp; skip hide() so the right-click completes. Modal cards survive focus changes.
        if !isMenuTracking && !isRightClickInProgress && !cardIsModal {
            hide()
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        // A key panel (search or content) resigns key when another window is clicked. Dismiss unless modal.
        if !cardIsModal {
            hide()
        }
    }

    @objc private func workspaceDidActivateApp(_ notification: Notification) {
        guard let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            ?? NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        // The selection's source app may activate without dismissing.
        if let sourceBundleID = currentContext?.sourceApp.bundleIdentifier,
           app.bundleIdentifier == sourceBundleID {
            return
        }
        // Grace period: a clipboard manager's self-dismiss can queue an activation for the destination app. Ignore it within 300 ms of opening.
        if sessionShowTime > 0,
           (ProcessInfo.processInfo.systemUptime - sessionShowTime) < PopupMetrics.focusSwitchGracePeriod {
            return
        }
        // Modal result cards survive focus changes (parity with appDidDeactivate).
        if cardIsModal { return }
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

    /// Presents a bar button's hover tooltip in the screen-space window, avoiding the expanded sub-bar so it flips above or below the bar.
    private func presentTooltip(text: String, localFrame: CGRect, effectiveTheme: String, isDark: Bool) {
        guard let panel, panel.isVisible else { return }
        let targetScreenFrame = convertHoverFrameToScreen(localFrame)
        guard !targetScreenFrame.isEmpty else { return }
        var avoidanceRects: [CGRect] = []
        if toastController.isShowing, toastController.currentPlacement != .overlay {
            avoidanceRects.append(toastController.panelFrame)
        }
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
        // An adjacent group must not replace the open row while the pointer is only
        // crossing it on the way in (#194). The triangle decides; other groups still switch now.
        if subBarController.isShowing,
           subBarController.activeState?.groupID != action.id,
           subBarController.isImmediateNeighbor(actionIndex: index) {
            beginAdjacentGroupAim(for: action, index: index, frame: frame)
            return
        }
        clearPendingGroupAim()
        subBarController.startDwell { [weak self] in
            guard let self else { return }
            self.showSubBar(for: action, index: index, frame: frame, isPinned: false)
        }
    }

    private func beginAdjacentGroupAim(for action: any Action, index: Int, frame: CGRect) {
        clearPendingGroupAim()
        pendingGroupAim = PendingGroupAim(groupID: action.id) { [weak self] in
            self?.showSubBar(for: action, index: index, frame: frame, isPinned: false)
        }
        let location = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let segment = aimSegment(for: location)
        notePointer(at: location, now: now)
        evaluateGroupAim(segment: segment, at: location, now: now)
    }

    private func trackPointerForGroupAim(at location: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let segment = aimSegment(for: location)
        notePointer(at: location, now: now)
        guard pendingGroupAim != nil else { return }
        evaluateGroupAim(segment: segment, at: location, now: now)
    }

    private func evaluateGroupAim(segment: AimSegment, at location: CGPoint, now: TimeInterval) {
        guard let pending = pendingGroupAim, subBarController.isShowing else {
            clearPendingGroupAim()
            return
        }
        guard hoveredAction?.id == pending.groupID else {
            clearPendingGroupAim()
            return
        }
        // The panel's shadow ring overlaps the main bar, so the triangle uses the visible row.
        let rect = subBarController.panelFrame.insetBy(
            dx: PopupMetrics.popupShadowInset,
            dy: PopupMetrics.popupShadowInset
        )
        let rested = segment.isNewMovement ? 0 : pointerRestDuration(at: location, now: now)
        let decision = SubBarAim.decision(
            previous: segment.previous,
            current: segment.current,
            subBarRect: rect,
            rested: rested
        )
        switch decision {
        case .switchToHovered:
            commitPendingGroupAim()
        case .keepMovingToward:
            subBarController.cancelGrace()
            if segment.isNewMovement || groupAimRestTask == nil {
                armGroupAimRest(for: pending.groupID)
            }
        case .keepResting:
            subBarController.cancelGrace()
            if groupAimRestTask == nil {
                armGroupAimRest(for: pending.groupID)
            }
        }
    }

    private func aimSegment(for location: CGPoint) -> AimSegment {
        guard let latest = latestPointerLocation else {
            return AimSegment(previous: nil, current: location, isNewMovement: false)
        }
        if hypot(location.x - latest.x, location.y - latest.y) < SubBarAim.movementEpsilon {
            return AimSegment(previous: previousPointerLocation, current: latest, isNewMovement: false)
        }
        return AimSegment(previous: latest, current: location, isNewMovement: true)
    }

    private func notePointer(at location: CGPoint, now: TimeInterval) {
        guard let latest = latestPointerLocation else {
            latestPointerLocation = location
            lastPointerMoveTime = now
            return
        }
        guard hypot(location.x - latest.x, location.y - latest.y) >= SubBarAim.movementEpsilon else { return }
        previousPointerLocation = latest
        latestPointerLocation = location
        lastPointerMoveTime = now
    }

    private func pointerRestDuration(at location: CGPoint, now: TimeInterval) -> TimeInterval {
        guard let latest = latestPointerLocation,
              hypot(location.x - latest.x, location.y - latest.y) < SubBarAim.movementEpsilon,
              let lastPointerMoveTime else { return 0 }
        return max(0, now - lastPointerMoveTime)
    }

    private func armGroupAimRest(for groupID: String) {
        groupAimRestTask?.cancel()
        let nanos = UInt64((SubBarAim.switchDwell * 1_000_000_000).rounded())
        groupAimRestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self.groupAimRestTask = nil
            guard let pending = self.pendingGroupAim, pending.groupID == groupID,
                  self.hoveredAction?.id == groupID,
                  self.subBarController.isShowing,
                  self.subBarController.activeState?.groupID != groupID else { return }
            // No further mouse event arrives while the pointer is still, so the timer is the rest half of SubBarAim.
            self.commitPendingGroupAim()
        }
    }

    private func commitPendingGroupAim() {
        let pending = pendingGroupAim
        clearPendingGroupAim()
        pending?.commit()
    }

    private func clearPendingGroupAim() {
        pendingGroupAim = nil
        groupAimRestTask?.cancel()
        groupAimRestTask = nil
    }

    private func showSubBar(for action: any Action, index: Int, frame: CGRect, isPinned: Bool) {
        clearPendingGroupAim()
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
            mainBarAbove: currentContext?.source == .ocr ? false : mainBarAbove,
            effectiveTheme: effectiveTheme,
            effectiveColorScheme: effectiveColorScheme,
            scale: scale,
            context: context,
            presenter: ActionCustomizationManager.shared,
            modeStore: modeStore,
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
                self.runAIPreset(prompt: prompt, title: preset.title, presetID: preset.id)
            },
            onRunLoadingAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext else { return }
                self.subBarController.hide()
                self.modeStore.isSubBarActive = false
                self.modeStore.activeSubGroupID = nil
                self.runLoadingAction(action, with: context, isSecondaryClick: clickIntent == .secondary)
            },
            onWillPerformAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext,
                      self.canPerformAction(action, in: context) else { return false }
                self.pendingDelivery = action.delivery
                self.pendingActionTitle = action.title
                self.pendingActionIcon = action.displayIcon(using: ActionCustomizationManager.shared)
                self.pendingActionID = action.id
                self.pendingActionRecommendedResult = action.chrome.recommendedResult
                self.pendingActionOutputKind = action.chrome.outputKind
                self.inFlightDeliveryContext = self.deliverySnapshot(for: action, clickIntent: clickIntent)
                return true
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .primary }
        )
        modeStore.subBarAbove = actuallyAbove
        updateToastPlacement()
    }

    /// Frontmost app when an in-place answer lands; pasting is only safe into the selection's app. Settable for tests.
    var frontmostBundleIDProvider: @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    /// Runs a palette instruction on the selection (standalone if `includeContext` is false). `replace` pastes over the selection (⏎);
    /// otherwise the answer streams into the card (⇧⏎).
    func runAIPrompt(_ instruction: String, replace: Bool, includeContext: Bool = true) {
        let replace = replace && currentActionContext?.selection.source != .ocr
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        let taskPrompt = includeContext
            ? PaletteAIPrompt.askAITaskPrompt(for: prompt)
            : PaletteAIPrompt.standaloneQuestionPrompt(for: prompt)
        let inputText: String? = includeContext ? nil : ""
        if replace {
            Log.ai.notice("Running a palette AI prompt, replacing the selection")
            runAIPromptReplacing(prompt: taskPrompt, inputText: inputText)
        } else {
            Log.ai.notice("Running a palette AI prompt into the result card")
            runAIPreset(prompt: taskPrompt, title: PaletteAIPrompt.toolTitle(for: prompt), inputText: inputText)
        }
    }

    /// Saves a palette instruction as a regular custom AI tool (reusing one with the same prompt) and runs it like `runAIPrompt`.
    func saveAndRunAIPrompt(_ instruction: String, replace: Bool) {
        let replace = replace && currentActionContext?.selection.source != .ocr
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        let manager = AIServiceManager.shared
        let existing = manager.preset(matchingPrompt: prompt)
        var preset = existing ?? manager.addCustomPreset(title: PaletteAIPrompt.toolTitle(for: prompt), prompt: prompt)
        usageStore.record(AIAction(presetID: preset.id, title: preset.title).id)
        if existing == nil {
            Log.ai.notice("Saved a palette prompt as AI tool \(preset.id, privacy: .public)")
        }

        // A reused tool already has its name; only a newly saved one asks the model for a title.
        let taskPrompt = existing == nil ? PaletteAIPrompt.saveToolTaskPrompt(for: prompt) : prompt
        let onTitle: ((String) -> Void)? = existing == nil ? { cleanTitle in
            let trimmed = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != preset.title else { return }
            preset.title = trimmed
            manager.updatePreset(preset)
        } : nil

        if replace {
            runAIPromptReplacing(
                prompt: taskPrompt,
                presetID: preset.id,
                loadingMessage: existing == nil ? String(localized: "Saved as AI tool · Replacing…") : nil,
                onGeneratedTitle: onTitle
            )
        } else {
            runAIPreset(
                prompt: taskPrompt,
                title: preset.title,
                presetID: preset.id,
                loadingMessage: existing == nil ? String(localized: "Saved as AI tool · Generating…") : nil,
                onGeneratedTitle: onTitle
            )
        }
    }

    /// Runs `prompt` on the selection and pastes the answer over it, with no card. Copies instead when the target can't paste
    /// or the frontmost app changed.
    func runAIPromptReplacing(prompt: String, presetID: String? = nil, loadingMessage: String? = nil, inputText: String? = nil, onGeneratedTitle: ((String) -> Void)? = nil) {
        guard let context = currentActionContext else {
            Log.ai.error("Cannot replace with AI: currentActionContext is nil")
            return
        }
        activeAIPresetID = presetID
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        let selection = context.selection
        let selectionText = inputText ?? selection.text
        let anchorFrame = panel?.frame ?? lastPopupFrame
        let targetCanPaste = PasteAvailability.effective(policy: selection.appPolicy, probe: modeStore.canPaste)
        let sourceBundleID = selection.sourceApp.bundleIdentifier

        hide()
        let session = aiSessionID
        toastController.showLoading(message: loadingMessage ?? String(localized: "Replacing…"), anchorFrame: anchorFrame) { [weak self] in
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
            do {
                let provider = AIServiceManager.shared.provider(forPresetID: self.activeAIPresetID)
                var accumulated = ""
                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    accumulated += chunk
                    if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                        onGeneratedTitle?(generated)
                    }
                }
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                    onGeneratedTitle?(generated)
                }
                let answer = AIRequestSupport.extractResultText(accumulated)
                guard !answer.isEmpty else { throw AIError.invalidResponse }
                let stillInSourceApp = sourceBundleID == nil || self.frontmostBundleIDProvider() == sourceBundleID
                let pastes = targetCanPaste != false && stillInSourceApp
                self.handleActionResult(pastes ? .paste(answer) : .copy(answer), delivery: nil, suppressDeliveryToast: true)
                let message = pastes
                    ? String(localized: "Replaced with AI result")
                    : (stillInSourceApp ? String(localized: "Copied AI result") : String(localized: "Copied — the app changed"))
                self.toastController.show(StatusFeedback(message: message, style: .success, symbolName: "sparkle"), anchorFrame: anchorFrame)
            } catch is CancellationError {
                self.toastController.hide()
            } catch let error as AIError where error == .cancelled {
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                Log.ai.error("Replacing with AI failed: \(error.localizedDescription)")
                self.toastController.show(StatusFeedback(error: error), anchorFrame: anchorFrame)
            }
        }
        activeStreamingTask = task
    }

    /// Runs a follow-up instruction on the card's current text. The card re-streams in place and diffs against the text it ran on.
    func runFollowUp(_ instruction: String) {
        guard let card = modeStore.resultCard, !card.isStreaming, !card.isError, currentActionContext != nil else { return }
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        Log.ai.notice("Running a follow-up instruction in the result card")
        refineCard(card, prompt: prompt)
    }

    /// The card a follow-up refines, kept so cancel or failure can restore it. Non-nil only while in flight.
    private var refiningPrevious: ResultCardPayload?

    /// Session history handed to follow-ups as labelled context.
    private(set) var cardConversation: AIConversation? {
        didSet { if cardConversation == nil { redoSteps = [] } }
    }

    /// Results undone with the version switcher, newest last; a new follow-up discards them.
    private var redoSteps: [AIConversation.Step] = []

    /// Moves the card one result back (-1) or forward (+1) in the session. The next follow-up continues from the shown result.
    func stepVersion(_ delta: Int) {
        guard var conversation = cardConversation, let card = modeStore.resultCard, !card.isStreaming, !card.isError else { return }
        if delta < 0 {
            guard conversation.steps.count > 1 else { return }
            redoSteps.append(conversation.steps.removeLast())
        } else {
            guard let step = redoSteps.popLast() else { return }
            conversation.steps.append(step)
        }
        cardConversation = conversation
        guard let shown = conversation.steps.last?.result else { return }
        showResultCard(text: shown, isError: false, title: card.title, icon: card.icon, isStreaming: false, session: aiSessionID, originalText: card.original, overrideOriginal: true)
    }

    /// Runs a follow-up inside the card: nothing hides, and the previous answer stays dimmed until the first chunk. Esc cancels;
    /// a failure restores the previous answer.
    private func refineCard(_ previous: ResultCardPayload, prompt: String) {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        let session = aiSessionID
        let sourceText = previous.text
        let conversation = cardConversation
            ?? AIConversation(original: previous.original ?? sourceText, steps: [])
        refiningPrevious = previous
        modeStore.isProcessingAI = true
        freezeCardSizeForRefinement()
        modeStore.resultCard = ResultCardPayload(
            text: sourceText,
            isError: false,
            title: previous.title,
            icon: nil,
            isStreaming: true,
            original: previous.original,
            isRefining: true
        )

        let task = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    self.activeStreamingTask = nil
                    self.modeStore.isProcessingAI = false
                }
            }
            // The card is the only render target; chunks after leaving content mode or session end are dropped.
            @MainActor func stillRefining() -> Bool {
                if Task.isCancelled { return false }
                if session != self.aiSessionID { return false }
                if self.modeStore.mode != .content { return false }
                return self.refiningPrevious != nil
            }
            do {
                let provider = AIServiceManager.shared.provider(forPresetID: self.activeAIPresetID)
                var accumulated = ""
                let activeTitle = previous.title
                for try await chunk in provider.processStream(refining: conversation, instruction: prompt, currentText: sourceText) {
                    guard stillRefining() else { return }
                    accumulated += chunk
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        self.showResultCard(text: cleaned, isError: false, title: activeTitle, isStreaming: true, session: session, originalText: previous.original, overrideOriginal: true)
                    }
                }
                guard stillRefining() else { return }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    self.restoreRefiningCard()
                    self.toastController.show(StatusFeedback(message: String(localized: "No response generated"), style: .error), anchorFrame: self.panel?.frame)
                } else {
                    self.refiningPrevious = nil
                    self.redoSteps = []
                    self.cardConversation = conversation.appending(instruction: prompt, result: finalResponse)
                    self.showResultCard(text: finalResponse, isError: false, title: activeTitle, isStreaming: false, session: session, originalText: previous.original, overrideOriginal: true)
                }
            } catch is CancellationError {
                // cancelFollowUp / hide already put the card back or took it down.
            } catch let error as AIError where error == .cancelled {
                // Same as above: cancelFollowUp / hide already restored the card.
            } catch {
                guard stillRefining() else { return }
                Log.ai.error("Follow-up failed in the result card: \(error.localizedDescription)")
                self.restoreRefiningCard()
                self.toastController.show(StatusFeedback(error: error), anchorFrame: self.panel?.frame)
            }
        }
        activeStreamingTask = task
    }

    /// Freezes the card at its current size so streaming refinements don't re-measure it per chunk. The body scrolls if needed.
    /// A card the user already resized is left alone.
    private func freezeCardSizeForRefinement() {
        guard !modeStore.isSurfaceUserSized, let panel else { return }
        let frozen = Self.cardSize(forPanelSize: panel.frame.size)
        guard frozen.width >= PopupMetrics.aiCardMinWidth, frozen.height >= PopupMetrics.aiCardMinHeight else { return }
        modeStore.resultCardSize = frozen
        modeStore.isSurfaceUserSized = true
    }

    /// The card's size inside a panel frame: the panel minus the transparent shadow ring.
    static func cardSize(forPanelSize size: CGSize) -> CGSize {
        CGSize(width: size.width - 2 * PopupMetrics.popupShadowInset, height: size.height - 2 * PopupMetrics.popupShadowInset)
    }

    /// Puts the answer the follow-up was refining back, settled, with the field focused again.
    private func restoreRefiningCard() {
        guard let previous = refiningPrevious else { return }
        refiningPrevious = nil
        modeStore.isProcessingAI = false
        showResultCard(text: previous.text, isError: previous.isError, title: previous.title, icon: previous.icon, isStreaming: false, session: aiSessionID, originalText: previous.original, overrideOriginal: true, canFollowUp: previous.canFollowUp)
    }

    /// Esc while a follow-up streams: stop it and keep the previous answer on screen.
    func cancelFollowUp() {
        guard refiningPrevious != nil else { return }
        Log.ai.info("Follow-up cancelled in the result card")
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        restoreRefiningCard()
    }

    /// Focuses the card's instruction field on the next run-loop turn; a @FocusState request during the mode change is dropped on macOS.
    private func focusCardField() {
        guard let panel, panel.isVisible, modeStore.mode == .content else { return }
        guard let field = Self.findEditableTextField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    /// The first editable text field in a view tree (the result card's follow-up field), or nil.
    static func findEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = findEditableTextField(in: subview) { return found }
        }
        return nil
    }

    func runAIPreset(prompt: String, title: String, presetID: String? = nil, loadingMessage: String? = nil, inputText: String? = nil, onGeneratedTitle: ((String) -> Void)? = nil) {
        activeAIPresetID = presetID
        guard let context = currentActionContext else {
            Log.ai.error("Cannot run AI preset: currentActionContext is nil")
            return
        }
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        let selection = context.selection
        let selectionText = inputText ?? selection.text
        let originalForCard = inputText != nil ? (inputText!.isEmpty ? nil : inputText) : nil
        let overrideOriginal = inputText != nil
        let anchorFrame = panel?.frame ?? lastPopupFrame
        let targetCanPaste = PasteAvailability.effective(policy: selection.appPolicy, probe: modeStore.canPaste)

        hide()
        let session = aiSessionID

        toastController.showLoading(message: loadingMessage ?? String(localized: "Generating…"), anchorFrame: anchorFrame) { [weak self] in
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
            var activeTitle = title

            do {
                let provider = AIServiceManager.shared.provider(forPresetID: self.activeAIPresetID)

                var accumulated = ""

                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    accumulated += chunk
                    if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                        activeTitle = newTitle
                        onGeneratedTitle?(newTitle)
                    }
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        if !hasYielded {
                            hasYielded = true
                            self.toastController.hide()
                            let canPaste = targetCanPaste
                            guard !Task.isCancelled, session == self.aiSessionID else { return }
                            self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        }
                        self.showResultCard(text: cleaned, isError: false, title: activeTitle, isStreaming: true, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                    }
                }

                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                self.toastController.hide()
                if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                    activeTitle = newTitle
                    onGeneratedTitle?(newTitle)
                }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        self.showResultCard(text: "No response generated", isError: true, title: activeTitle, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                    }
                } else {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                    }
                    // A fresh run starts the card's session history; refineCard extends it.
                    self.redoSteps = []
                    if inputText == nil {
                        self.cardConversation = AIConversation(original: selectionText, steps: [.init(instruction: prompt, result: finalResponse)])
                    } else {
                        self.cardConversation = AIConversation(original: finalResponse, steps: [.init(instruction: prompt, result: finalResponse)])
                    }
                    self.showResultCard(text: finalResponse, isError: false, title: activeTitle, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                    ActionSoundPolicy.play(owner: presetID.map { AIAction(presetID: $0, title: "").id })
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
                self.showResultCard(text: message, isError: true, title: title, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
            }
        }
        activeStreamingTask = task
    }
    
    /// Settable in `init` so the effect-delivery tests can inject a recording handler.
    var resultHandler: ActionResultHandler

    // MARK: - Decision 8: ActionResult Tree-Walk

    /// Inputs to the paste-vs-copy decision, captured synchronously when an action performs. `nil` (explicit user requests) means never re-decided.
    struct DeliveryContext {
        let policy: AppPolicyContext
        let clickIntent: ActionResultDelivery.ClickIntent
        /// Declared delivery (secondary outcome and per-click toasts); nil means none.
        let delivery: ActionDelivery?
        /// Target app for delivery, captured synchronously; `exitKeyMode()` reactivates this app on hide.
        let application: NSRunningApplication?
        /// The user's per-action override if one was configured in Action Editor.
        let userOverride: ResultDeliveryPreference?
        /// The author's recommended delivery mode.
        let recommendedResult: ActionResultDeliveryMode?
        /// The action's uncommitted output kind.
        let outputKind: ActionOutputKind?
        /// The performing action's title — the result card header. nil for explicit user requests.
        let actionTitle: String?
        /// Display icon for the card header (customization-resolved).
        let actionIcon: ActionIcon?
        /// Input/destination requirements rechecked immediately before effects are executed.
        let inputRequirement: ActionInputRequirement?
        let requiresPasteTarget: Bool
        /// The selection context captured before any early-close (loading actions), used to re-show
        /// the popup as a preview card. nil when the popup never closed.
        let selection: SelectionContext?

        /// Resolves a declared secondary on a secondary click. Consuming it sets `clickIntent` to `.primary` and moves
        /// `secondaryToast` to `primaryToast`, so explicit outcomes aren't downgraded by the clipboard invariant.
        func consumeDeclaredSecondary(for result: ActionResult) -> (result: ActionResult, delivery: DeliveryContext) {
            guard clickIntent == .secondary, let declared = delivery?.secondary else {
                return (result, self)
            }
            let consumed = DeliveryContext(
                policy: policy,
                clickIntent: .primary,
                delivery: ActionDelivery(secondary: nil, primaryToast: delivery?.secondaryToast, secondaryToast: nil),
                application: application,
                userOverride: userOverride,
                recommendedResult: recommendedResult,
                outputKind: outputKind,
                actionTitle: actionTitle,
                actionIcon: actionIcon,
                inputRequirement: inputRequirement,
                requiresPasteTarget: requiresPasteTarget,
                selection: selection
            )
            return (declared, consumed)
        }
    }

    /// Snapshots delivery inputs synchronously, before any dismissal or await.
    func deliverySnapshot(for action: (any Action)? = nil, clickIntent: ActionResultDelivery.ClickIntent? = nil) -> DeliveryContext {
        let intent = clickIntent ?? pendingClickIntent
        let actionDelivery = action?.delivery ?? pendingDelivery
        let title = action?.title ?? pendingActionTitle
        let icon = action?.displayIcon(using: ActionCustomizationManager.shared) ?? pendingActionIcon
        let actionID = action?.id ?? pendingActionID
        let targetApp = previousFrontmostApp ?? (frontmostApplicationProvider()?.bundleIdentifier != Bundle.main.bundleIdentifier ? frontmostApplicationProvider() : previousFrontmostApp)
        let override = actionID.flatMap { ActionCustomizationManager.shared.override(for: $0)?.deliveryPreference }
        let rec = action?.chrome.recommendedResult ?? pendingActionRecommendedResult
        let outKind = action?.chrome.outputKind ?? pendingActionOutputKind
        return DeliveryContext(
            policy: currentActionContext?.selection.appPolicy ?? .default,
            clickIntent: intent,
            delivery: actionDelivery,
            application: targetApp,
            userOverride: override,
            recommendedResult: rec,
            outputKind: outKind,
            actionTitle: title,
            actionIcon: icon,
            inputRequirement: (action as? any ActionWithRules).map { $0.rules?.requirements?.input ?? .text },
            requiresPasteTarget: (action as? any ActionWithRules)?.rules?.requirements?.requiresPasteTarget ?? false,
            selection: currentActionContext?.selection
        )
    }

    /// Whether the target app is still frontmost; async paste must not post into a new foreground window.
    private func isTargetApplicationActive(_ targetApp: NSRunningApplication?) -> Bool {
        guard let targetApp else { return true }
        guard let frontmost = frontmostApplicationProvider() else { return true }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }
        return frontmost.processIdentifier == targetApp.processIdentifier
    }

    /// Declared paste-target requirements also apply to the async paste probe.
    private func requiredPasteTargetIsActive(_ delivery: DeliveryContext?) -> Bool {
        guard let delivery, delivery.requiresPasteTarget else { return true }
        return isTargetApplicationActive(delivery.application)
    }

    /// Routes a performed result into the tree-walk. The delivery snapshot is taken before `hide()` clears the live context, and
    /// is single-use: a later paste must never reuse a prior action's declaration.
    func deliverResult(_ result: ActionResult, delivery: DeliveryContext? = nil) {
        let resolvedDelivery = delivery ?? inFlightDeliveryContext ?? deliverySnapshot()
        let completedActionID = pendingActionID
        inFlightDeliveryContext = nil
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        pendingActionID = nil
        pendingActionRecommendedResult = nil
        pendingActionOutputKind = nil
        let (deliveredResult, effectiveDelivery) = resolvedDelivery.consumeDeclaredSecondary(for: result)
        let effectiveResult = normalizeOCRResult(deliveredResult, delivery: effectiveDelivery)
        if shouldDismiss(effectiveResult, delivery: effectiveDelivery) {
            hide()
        }
        handleActionResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast, completionActionID: completedActionID)
    }

    private func copyOnlyOCRResult(_ result: ActionResult) -> ActionResult {
        switch result {
        case .paste(let text), .cut(let text): return .copy(text)
        case .pasteContent(let payload): return .copyContent(payload)
        case .simulatePaste: return .none
        case .sequence(let items): return .sequence(items.map(copyOnlyOCRResult))
        default: return result
        }
    }

    private func normalizeOCRResult(_ result: ActionResult, delivery: DeliveryContext?) -> ActionResult {
        let isOCRDelivery = delivery?.selection?.source == .ocr
            || (delivery == nil && currentContext?.source == .ocr)
        let ocrSafe = isOCRDelivery ? copyOnlyOCRResult(result) : result
        guard let delivery, delivery.inputRequirement != nil || delivery.requiresPasteTarget else { return ocrSafe }

        let selection = delivery.selection
        let input = delivery.inputRequirement ?? .optional
        let hasText = !(selection?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let liveAndCurrent = selection?.source == .selection
            && (selection.map(selectionIsCurrent) ?? false)
            && isTargetApplicationActive(delivery.application)
        let inputSatisfied: Bool
        switch input {
        case .optional: inputSatisfied = true
        case .text: inputSatisfied = hasText
        case .liveSelection: inputSatisfied = hasText && liveAndCurrent
        case .editableSelection: inputSatisfied = hasText && liveAndCurrent && selection?.isEditable == true
        }
        let pasteTargetSatisfied = !delivery.requiresPasteTarget
            || (selection?.pasteTargetAvailable == true
                && PasteAvailability.effective(policy: delivery.policy, probe: selection?.pasteTargetAvailable) == true
                && isTargetApplicationActive(delivery.application))
        return inputSatisfied && pasteTargetSatisfied ? ocrSafe : .none
    }

    /// Walks a performed result: presentation renders in the popup, leaf effects go to the effect handler. Dismissal is decided
    /// once at the top level. A top-level `.toast` suppresses delivery toasts, and a `.sequence` runs its items in order.
    @discardableResult
    func handleActionResult(_ result: ActionResult, delivery: DeliveryContext? = nil, suppressDeliveryToast: Bool = false, completionActionID: String? = nil, isFinalStep: Bool = true) -> Task<Void, Never>? {
        let (selectedResult, effectiveDelivery) = delivery?.consumeDeclaredSecondary(for: result) ?? (result, delivery)
        let effectiveResult = normalizeOCRResult(selectedResult, delivery: effectiveDelivery)
        let effectiveSuppressToast = suppressDeliveryToast || effectiveResult.containsToast
        switch effectiveResult {
        case .toast(let feedback):
            presentToast(feedback)
            ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
            return nil
        case .openConfiguration(let request):
            presentConfiguration(for: request)
            return nil
        case .sequence(let items):
            return Task { @MainActor in
                for (index, item) in items.enumerated() {
                    let isLast = isFinalStep && index == items.count - 1
                    await self.handleActionResult(item, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast, completionActionID: completionActionID, isFinalStep: isLast)?.value
                }
            }
        default:
            return handleEffect(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast, completionActionID: completionActionID, isFinalStep: isFinalStep)
        }
    }

    /// Routes a leaf effect to DefaultActionResultHandler. A thrown error becomes a dismissing error toast. Applies the paste-vs-copy
    /// decision (`.paste` becomes `.copy` on force-copy, policy, or an unavailable target); nil `delivery` passes through.
    @discardableResult
    private func handleEffect(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false, completionActionID: String? = nil, isFinalStep: Bool = true) -> Task<Void, Never> {
        let effect = result
        return Task { @MainActor in
            do {
                let resolved = await resolveDelivery(effect, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast)
                guard requiredPasteTargetIsActive(delivery) else { return }
                if case .text(let text) = resolved.result {
                    // Preview: show the text in the card and deliver nothing; the popup stays open. Probe paste if it was skipped,
                    // so the card gates Paste on a real answer (unknown normalizes to cannot-paste).
                    if modeStore.canPaste == nil {
                        modeStore.canPaste = await pasteProbe.canPaste(in: delivery?.application, policy: delivery?.policy ?? .default) ?? false
                    }
                    showResultCard(text: text, isError: false, title: delivery?.actionTitle ?? "Action", icon: delivery?.actionIcon, session: aiSessionID, canFollowUp: false)
                    ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
                    return
                }
                if case .file(let filePayload) = resolved.result {
                    showResultCard(
                        text: filePayload.displayName,
                        isError: false,
                        title: delivery?.actionTitle ?? filePayload.displayName,
                        icon: delivery?.actionIcon,
                        session: aiSessionID,
                        canFollowUp: false,
                        file: filePayload
                    )
                    ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
                    return
                }
                // A detached-surface result suspends scroll dismissal for the rest of the session.
                isScrollDismissalSuspended = resolved.result.suspendsScrollDismissal
                try await resultHandler.handle(resolved.result, in: panel?.contentView, targetApp: delivery?.application,
                                               isSelectionCurrent: { [weak self] selection in
                    self?.selectionIsCurrent(selection) == true
                })
                ActionSoundPolicy.play(owner: completionActionID, result: resolved.result, isFinalStep: isFinalStep)
                let toastToShow: StatusFeedback? = {
                    if let toast = resolved.toast {
                        if case .saveFile = resolved.result {
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        }
                        return toast
                    }
                    if delivery == nil {
                        switch resolved.result {
                        case .saveFile:
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        case .copyFile:
                            return StatusFeedback(message: String(localized: "Copied File"), style: .success, symbolName: "doc.on.doc")
                        default:
                            return nil
                        }
                    }
                    return nil
                }()
                if let toast = toastToShow, !suppressDeliveryToast {
                    toastController.show(toast, anchorFrame: panel?.frame ?? lastPopupFrame)
                }
            } catch {
                handleActionResult(.toast(StatusFeedback(error: error)))
            }
        }
    }

    /// Decides a text result's delivery and companion toast from the snapshot. A nil `delivery` passes through with no toast.
    /// The paste probe runs only when a paste outcome is on the table, since only `.paste` can downgrade to `.copy`.
    internal var selectionIsCurrent: @MainActor (SelectionContext) -> Bool = { _ in true }
    internal private(set) var lastDeliveryStatus: SelectionReadStatus?

    private func resolveDelivery(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false) async -> (result: ActionResult, toast: StatusFeedback?) {
        guard let delivery else { return (result, nil) }
        let selected = ActionResultDelivery.select(
            raw: result,
            clickIntent: delivery.clickIntent,
            delivery: delivery.delivery ?? .none,
            preference: delivery.userOverride,
            recommendedResult: delivery.recommendedResult,
            outputKind: delivery.outputKind
        )
        let couldPaste = delivery.selection?.source != .ocr && isPaste(selected)
        let isTargetActive = isTargetApplicationActive(delivery.application)
            && (delivery.selection.map(selectionIsCurrent) ?? true)
        var canPaste: Bool
        if !couldPaste || !isTargetActive {
            canPaste = false
        } else if !PasteAvailability.needsProbe(policy: delivery.policy) {
            canPaste = PasteAvailability.effective(policy: delivery.policy, probe: nil) ?? false
        } else {
            canPaste = await pasteProbe.canPaste(in: delivery.application, policy: delivery.policy) ?? false
        }
        // A target may change while the AX paste probe is suspended.
        if couldPaste, !isTargetApplicationActive(delivery.application)
            || !(delivery.selection.map(selectionIsCurrent) ?? true) {
            canPaste = false
        }
        if couldPaste, !isTargetActive || !(delivery.selection.map(selectionIsCurrent) ?? true)
            || !isTargetApplicationActive(delivery.application) {
            lastDeliveryStatus = .targetChanged
            Log.selection.debug("delivery outcome: targetChanged")
        } else {
            lastDeliveryStatus = nil
        }
        let resolved = ActionResultDelivery.resolve(
            raw: result,
            clickIntent: delivery.clickIntent,
            canPaste: canPaste,
            delivery: delivery.delivery ?? .none,
            preference: delivery.userOverride,
            recommendedResult: delivery.recommendedResult,
            outputKind: delivery.outputKind
        )
        return (resolved.result, suppressDeliveryToast ? nil : resolved.toast)
    }

    private func isPaste(_ result: ActionResult?) -> Bool {
        guard let result else { return false }
        switch result {
        case .paste, .pasteContent:
            return true
        default:
            return false
        }
    }

    private func isText(_ result: ActionResult) -> Bool {
        guard case .text = result else { return false }
        return true
    }

    /// Top-level dismissal: the popup stays open only when the resolved outcome is `.text` (preview) or `.file`. Mirrors the resolver's
    /// Select step so dismissal matches the delivered outcome. `canPaste` does not matter here.
    private func shouldDismiss(_ result: ActionResult, delivery: DeliveryContext) -> Bool {
        let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
        let resolved = ActionResultDelivery.resolve(
            raw: effectiveResult,
            clickIntent: effectiveDelivery.clickIntent,
            canPaste: false,
            delivery: effectiveDelivery.delivery ?? .none,
            preference: effectiveDelivery.userOverride,
            recommendedResult: effectiveDelivery.recommendedResult,
            outputKind: effectiveDelivery.outputKind
        ).result
        if isText(resolved) { return false }
        if case .file = resolved { return false }
        return resolved.dismissesPopup
    }

    /// Runs a leaf action from a per-action hotkey. Reuses the on-screen session if up; otherwise opens on the selection so paste and preview have a delivery context.
    func runBoundAction(_ action: any Action, with context: ActionContext, pasteAvailable: Bool? = nil) {
        guard canPerformAction(action, in: context) else { return }
        if panel?.isVisible != true {
            show(for: context.selection, pasteAvailable: pasteAvailable)
        } else if let pasteAvailable {
            modeStore.canPaste = pasteAvailable
        }
        if ActionIdentity.isAIPreset(action) {
            guard let preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
            runAIPreset(prompt: AIServiceManager.shared.promptForPreset(preset), title: preset.title, presetID: preset.id)
            return
        }
        runAction(action, with: context, isSecondaryClick: false)
    }

    /// Perform-time gate for clicks, group actions, and hotkeys. Visibility is recomputed from the captured context; source-bound
    /// requirements also check the selection generation and target app.
    private func canPerformAction(_ action: any Action, in context: ActionContext) -> Bool {
        guard action.isEnabled(for: context) else { return false }
        guard let ruledAction = action as? any ActionWithRules else { return true }
        let requirements = ruledAction.rules?.requirements ?? ActionRequirements()
        let selection = context.selection
        let liveAndCurrent = selection.source == .selection
            && selectionIsCurrent(selection)
            && isTargetApplicationActive(previousFrontmostApp)
        switch requirements.input {
        case .optional, .text:
            break
        case .liveSelection:
            guard liveAndCurrent else { return false }
        case .editableSelection:
            guard liveAndCurrent, selection.isEditable == true else { return false }
        }
        if requirements.requiresPasteTarget {
            guard context.pasteTargetAvailable == true,
                  PasteAvailability.effective(policy: selection.appPolicy, probe: context.pasteTargetAvailable) == true,
                  isTargetApplicationActive(previousFrontmostApp) else { return false }
        }
        return true
    }

    /// Performs an action directly for the right-click path, which the SwiftUI button never fires. Builds the delivery context
    /// from `isSecondaryClick`.
    func runAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        guard canPerformAction(action, in: context) else { return }
        if action.chrome.showsLoading {
            runLoadingAction(action, with: context, isSecondaryClick: isSecondaryClick)
            return
        }
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // Snapshot the declared delivery and title into the DeliveryContext. Pending state stays untouched: no onWillPerformAction precedes this path.
        let delivery = deliverySnapshot(for: action, clickIntent: clickIntent)
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
                let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
                if self.shouldDismiss(effectiveResult, delivery: effectiveDelivery) {
                    self.hide()
                }
                self.handleActionResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast)
                self.inFlightDeliveryContext = nil
            } catch {
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                self.handleActionResult(.toast(StatusFeedback(error: error)))
                self.inFlightDeliveryContext = nil
            }
        }
    }

    /// Performs a `showsLoading` action with early close: the popup hides, a spinner toast attaches to its last frame, and the
    /// result settles the toast.
    func runLoadingAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        guard canPerformAction(action, in: context) else { return }
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // Snapshot the declared delivery and title into the DeliveryContext; pending state stays untouched.
        let delivery = deliverySnapshot(for: action, clickIntent: clickIntent)
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
                let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
                await self.settleLoadingResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast, completionActionID: action.id)
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

    /// Settles a loading action's spinner toast from its result: `.toast` swaps in, a delivery toast swaps in, and other
    /// results fade the spinner. With `suppressDeliveryToast`, the script toast owns the toast (one per run).
    private func settleLoadingResult(_ result: ActionResult, delivery: DeliveryContext, suppressDeliveryToast: Bool = false, completionActionID: String? = nil, isFinalStep: Bool = true) async {
        let (selectedResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
        let effectiveResult = normalizeOCRResult(selectedResult, delivery: effectiveDelivery)
        let effectiveSuppressToast = suppressDeliveryToast || effectiveResult.containsToast
        switch effectiveResult {
        case .toast(var feedback):
            feedback.keepVisible = false
            toastController.show(feedback)
            ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
        case .openConfiguration(let request):
            toastController.hide()
            presentConfiguration(for: request)
        case .sequence(let items):
            for (index, item) in items.enumerated() {
                let isLast = isFinalStep && index == items.count - 1
                await settleLoadingResult(item, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast, completionActionID: completionActionID, isFinalStep: isLast)
            }
        default:
            let effect = effectiveResult
            do {
                let resolved = await resolveDelivery(effect, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast)
                guard requiredPasteTargetIsActive(effectiveDelivery) else {
                    toastController.hide()
                    return
                }
                if case .text(let text) = resolved.result {
                    // Preview on a loading action: hide the spinner and re-show the popup as a card at the original selection, re-probing paste.
                    toastController.hide()
                    if let selection = effectiveDelivery.selection {
                        let canPaste = await pasteProbe.canPaste(in: effectiveDelivery.application, policy: effectiveDelivery.policy) ?? false
                        guard requiredPasteTargetIsActive(effectiveDelivery) else {
                            toastController.hide()
                            return
                        }
                        show(for: selection, pasteAvailable: canPaste)
                        showResultCard(text: text, isError: false, title: effectiveDelivery.actionTitle ?? "Action", icon: effectiveDelivery.actionIcon, session: aiSessionID, canFollowUp: false)
                    }
                    ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
                    return
                }
                if case .file(let filePayload) = resolved.result {
                    toastController.hide()
                    if let selection = effectiveDelivery.selection {
                        let canPaste = await pasteProbe.canPaste(in: effectiveDelivery.application, policy: effectiveDelivery.policy) ?? false
                        show(for: selection, pasteAvailable: canPaste)
                        showResultCard(
                            text: filePayload.displayName,
                            isError: false,
                            title: effectiveDelivery.actionTitle ?? filePayload.displayName,
                            icon: effectiveDelivery.actionIcon,
                            session: aiSessionID,
                            canFollowUp: false,
                            file: filePayload
                        )
                    }
                    ActionSoundPolicy.play(owner: completionActionID, isFinalStep: isFinalStep)
                    return
                }
                try await resultHandler.handle(resolved.result, in: panel?.contentView)
                ActionSoundPolicy.play(owner: completionActionID, result: resolved.result, isFinalStep: isFinalStep)
                let toastToShow: StatusFeedback? = {
                    if let toast = resolved.toast {
                        if case .saveFile = resolved.result {
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        }
                        return toast
                    }
                    return nil
                }()
                if let toast = toastToShow, !effectiveSuppressToast {
                    toastController.swapTo(toast)
                } else if !effectiveSuppressToast {
                    toastController.hide()
                }
            } catch {
                await settleLoadingResult(.toast(StatusFeedback(error: error)), delivery: effectiveDelivery)
            }
        }
    }

    /// Feedback lives in its own window; the action panel never grows or shrinks for it.
    func updateToastPlacement() {
        guard toastController.isShowing, toastController.currentPlacement != .overlay, let panel else { return }
        let avoidance = subBarController.isShowing ? [subBarController.panelFrame] : []
        toastController.reposition(anchorFrame: panel.frame, avoidanceRects: avoidance)
    }

    /// Spinner shown while Capture Text recognizes; the OCR popup, a failure toast, or `hideCaptureProgress` replaces it.
    func showCaptureProgress(at point: CGPoint, onCancel: @escaping () -> Void) {
        toastController.show(StatusFeedback(message: String(localized: "Recognizing text…"), style: .info, isLoading: true),
                             placement: .nearCursor(point), onCancel: onCancel)
        captureToastPresentationID = toastController.presentationID
    }

    func hideCaptureProgress() {
        guard isCaptureToastCurrent, toastController.isLoading else { return }
        toastController.hide()
        captureToastPresentationID = nil
    }

    /// Shows feedback near an explicit point or the current cursor; popup/group frames are
    /// avoidance rectangles, not the position of the toast.
    public func showToast(_ feedback: StatusFeedback, at point: CGPoint? = nil) {
        let avoidance = subBarController.isShowing ? [subBarController.panelFrame] : []
        let placement = point.map { ToastPlacement.nearCursor($0) }
        toastController.show(feedback, anchorFrame: panel?.frame ?? lastPopupFrame,
                             placement: placement, avoidanceRects: avoidance)
    }

    /// Status feedback uses its own cursor-relative window even after the popup has hidden.
    private func presentToast(_ feedback: StatusFeedback) {
        showToast(feedback)
    }

    /// Config-open: posts the configuration notification so Preferences presents the action's editor.
    private func presentConfiguration(for request: ConfigurationRequest) {
        NotificationCenter.default.post(
            name: .openClipOpenActionConfiguration,
            object: nil,
            userInfo: ["request": request]
        )
    }
}
