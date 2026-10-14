// PopupView.swift
// OpenClip
//
// Renders the main floating action bar popup view presenting available actions, transform menus,
// inline completion buttons, the action-search palette, and the native AI result card (which
// replaces the bar with ResultCardView in content mode).
import SwiftUI
import AppKit
import CoreGraphics
import Core
import SDWebImageSwiftUI


// MARK: - Popup View

@MainActor
public struct PopupView: View {
    public let actions: [any Action]
    public let allActions: [any Action]
    public let context: ActionContext
    private let alternateSearchContext: SelectionContext?
    private let onSearchContextChanged: (@MainActor (SelectionContext) -> Void)?
    public let onResult: @MainActor (ActionResult) -> Void
    public let onContentSizeChange: (@MainActor (CGSize) -> Void)?
    /// active=true when AI is running or showing result; cardAboveBar=true when the card should render above the bar
    public let onAIStateChange: (@MainActor (Bool, Bool) -> Void)?
    /// Called with (resultText, isError, title, isStreaming) when the AI result is updated to show in the AI result
    /// card; `title` is the producing preset's title (falls back to "AI Tools" in the card).
    public let onAIResult: (@MainActor (String, Bool, String, Bool) -> Void)?
    /// Called when the sub-bar's active state changes, allowing the controller to suppress recentering.
    public let onSubBarActiveChanged: (@MainActor (Bool) -> Void)?
    /// Called when a group action or AI tools launcher requests opening/toggling the standalone sub-bar.
    public let onRequestSubBarToggle: (@MainActor (any Action, Int, CGRect) -> Void)?
    /// Called when the cursor dwells on a group button to open the transient sub-bar.
    public let onRequestSubBarDwell: (@MainActor (any Action, Int, CGRect) -> Void)?
    /// Called when the cursor leaves a group button to cancel dwell / start grace.
    public let onCancelSubBarDwell: (@MainActor () -> Void)?
    /// Called when the AI result card should collapse back to the bar (back chevron).
    public let onExitContent: @MainActor () -> Void
    /// Called when the result card should close outright (Esc) — the popup goes away rather than
    /// falling back to the bar.
    public let onDismissContent: @MainActor () -> Void
    /// Called as the result card or search header is dragged, so the controller can move the panel.
    public let onCardDrag: (@MainActor (ResultCardDragPhase) -> Void)?
    /// Called as a resize handle of the result card or the search palette is dragged, so the
    /// controller can resize the surface (and the panel around it) and remember the size.
    public let onResize: (@MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void)?
    /// Called when the user taps the pin button on the result card. The controller reacts by
    /// setting `hasUserMovedCard = true` (making the card modal) and toggling `modeStore.isCardPinned`.
    public let onPinCard: (@MainActor () -> Void)?
    /// The AI result card's Paste/Copy buttons — explicit user requests routed through the
    /// controller's keep-open card-effect door (bypasses the paste-vs-copy re-decision).
    public let onCardEffect: @MainActor (ActionResult) -> Void
    /// Called when the hovered action changes (nil when nothing hovered). Drives the hovered-row
    /// tracking used by the right-click path.
    public let onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)?
    /// Opens a scoped palette for a bar row's sub-actions (group rows via `.openSubActions` and the
    /// AI Tools launcher): the controller resolves + owns the SearchScope and enters search mode.
    public let onEnteredScopedSearch: (@MainActor (any Action, CGRect?) -> Void)?
    /// Sets the horizontal anchor mode on the popup panel before pagination or mode transitions.
    public let onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)?
    /// Called when an action is actually run (bar / palette / AI), so the controller can record usage.
    public let onActionPerformed: (@MainActor (String) -> Void)?
    /// Called right before an action performs (before `onResult` can fire), so the controller can
    /// snapshot the action's declared delivery for the paste-vs-copy decision. The intent is
    /// carried explicitly so the delivery snapshot matches the perform context.
    public let onWillPerformAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool)?
    /// Called when a `showsLoading` bar action is clicked: the controller early-closes the popup
    /// and runs the action via the loading toast flow instead of the inline perform path. Carries
    /// the same explicit intent as `onWillPerformAction`.
    public let onRunLoadingAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void)?
    /// Called when an AI preset action is run: the controller closes the popup and runs via the loading toast flow.
    public let onRunAI: (@MainActor (String) -> Void)?
    /// Runs a palette instruction (the "Ask AI" row or a recent prompt) on the selection:
    /// `(instruction, replace)` — paste the answer over the selection, or show the result card.
    /// nil falls back to the view's own card flow (preview/static hosts).
    public let onRunAIPrompt: (@MainActor (String, Bool, Bool) -> Void)?
    /// Saves the palette's typed query as a reusable AI tool and runs it (the "Save as AI tool"
    /// row), same flag. nil falls back to the view's own flow.
    public let onSaveAIPrompt: (@MainActor (String, Bool) -> Void)?
    /// Runs an instruction typed into the result card's follow-up field on the card's current
    /// text (the controller re-streams the card in place). nil hides the field.
    public let onFollowUp: (@MainActor (String) -> Void)?
    /// Cancels a follow-up in flight (Esc while the card refines), keeping the previous answer.
    public let onCancelFollowUp: (@MainActor () -> Void)?
    /// Submits the additional instruction typed for `modeStore.instructionRequest`:
    /// `(requestID, instruction)`. The controller resolves the preset's prompt and runs it.
    public let onSubmitInstruction: (@MainActor (UUID, String) -> Void)?
    /// Cancels the additional-instruction prompt without running anything.
    public let onCancelInstruction: (@MainActor () -> Void)?
    /// Returns the click intent captured at mouse-down for the current click, so the left-click
    /// perform path can thread a force-copy click (⇧-click) into the action context.
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent
    /// Shows the hover tooltip for a bar button in the controller's screen-space tooltip window:
    /// (text, button frame in popupHoverSpace, effective theme token, isDark). The controller
    /// converts the frame to screen coordinates and places the tooltip via TooltipPlacer so it
    /// escapes the panel's clipping and avoids the expanded sub-bar.
    public let onShowTooltip: (@MainActor (String, CGRect, String, Bool) -> Void)?
    /// Hides the screen-space hover tooltip.
    public let onHideTooltip: (@MainActor () -> Void)?
    /// True when this is a static preview — hover tracking is disabled entirely so the
    /// preview never reacts to (or leaks into) the real popup's shared hover state.
    public let screenWidth: CGFloat
    private let isStatic: Bool

    @Setting(SettingKey.popupTheme) private var selectedTheme
    @Setting(SettingKey.popupThemeColor) private var themeColor
    @Setting(SettingKey.popupScale) private var popupScale
    @Setting(SettingKey.popupPageSize) private var pageSize
    @Setting(SettingKey.popupFitToWidth) private var fitToWidth
    @Setting(SettingKey.showSearchAllActions) private var showSearchAllActions
    @Setting(SettingKey.contextualActionsEnabled) private var contextualActionsEnabled
    @Setting(SettingKey.disabledContextualActionIDs) private var disabledContextualIDs
    @Setting(SettingKey.contextualPillPosition) private var contextualPillPosition
    @Setting(SettingKey.popupAlignment) private var popupAlignment
    @Environment(\.colorScheme) private var colorScheme

    private var themeCategory: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: selectedTheme)
    }

    /// The color scheme the popup content should render as — matching the effective theme
    /// (classic or glass) so `.primary`/`.secondary` and the glass material agree with the
    /// chosen appearance even when the system is the opposite.
    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var effectiveTheme: String {
        if themeCategory == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }
    
    @Setting(SettingKey.completionCopyToClipboard) private var completionCopyToClipboard
    
    @State private var currentPage = 0
    /// The hover state this bar reads. Deliberately *not* `@ObservedObject`: `location` publishes at
    /// event-monitor rate on every mouse move, and observing the whole object re-evaluates the entire
    /// body tree per move. Instead the view holds it unobserved and subscribes only to
    /// `hoverState.$location` via `.onReceive`, so `@State hoveredTarget` changes only when the
    /// hit-test result actually changes.
    private let hoverState: PopupHoverState
    /// Resolves user-customized action titles/icons (composition-injected, defaults to the shared
    /// customization manager — never a hidden singleton reference inside the Action extension).
    private let presenter: any ActionPresenting
    /// The mode this bar observes: the real popup uses the store injected by
    /// PopupWindowController; the static preview passes a throwaway store.
    @ObservedObject private var modeStore: PopupModeStore
    /// Requests entering/leaving search mode; the controller owns the key-window changes.
    private let onEnterSearch: @MainActor (CGRect?) -> Void
    private let onExitSearch: @MainActor () -> Void
    /// The popup session this view belongs to. Stamped into every streaming delivery so the
    /// controller can drop chunks from an abandoned stream (dismissed mid-stream, superseded).
    private let sessionID: UUID
    /// Hands the streaming task to the controller so hide() can cancel it immediately —
    /// session-scoped cancellation that never waits for SwiftUI view teardown.
    private let registerStreamingTask: @MainActor (Task<Void, Never>?) -> Void
    @ObservedObject private var aiManager = AIServiceManager.shared
    @State private var hoveredTarget: PopupHoverTarget?
    @State private var hoverFrames: [PopupHoverTarget: CGRect] = [:]
    @State private var isShowingCompletions: Bool = true
    @State private var isProcessingAI: Bool = false
    @State private var aiTask: Task<Void, Never>? = nil
    /// Captured once when the popup appears — never re-read from mouse location to avoid jitter.
    @State private var aiCardAboveBar: Bool = false
    @State private var glowOffset: CGFloat = -1.0
    /// Completions are computed exactly once per show — the selection text is fixed for this view's
    /// lifetime — and cached, so NSSpellChecker dictionary work never runs inside `body`.
    @State private var cachedCompletions: [String]
    @State private var tooltipPresenter = TooltipPresenter()

    private var scale: CGFloat { PopupMetrics.scaleMultiplier(for: popupScale) }
    @Namespace private var hoverHighlightNamespace

    private var buttonWidth: CGFloat { PopupMetrics.actionButtonWidth * scale }
    private var chevronWidth: CGFloat { PopupPageLayout.chevronWidth * scale }
    private var barButtonHeight: CGFloat { PopupMetrics.barButtonHeight * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }
    private var islandGap: CGFloat { PopupMetrics.splitIslandGap * scale }

    @MainActor
    public init(
        settingsStore: SettingsStore = DefaultSettingsStore.shared,
        actions: [any Action],
        allActions: [any Action]? = nil,
        context: ActionContext,
        alternateSearchContext: SelectionContext? = nil,
        onSearchContextChanged: (@MainActor (SelectionContext) -> Void)? = nil,
        screenWidth: CGFloat = NSScreen.main?.visibleFrame.width ?? 1440.0,
        initialAICardAboveBar: Bool = false,
        hoverState: PopupHoverState = .shared,
        presenter: any ActionPresenting = ActionCustomizationManager.shared,
        isStatic: Bool = false,
        modeStore: PopupModeStore = PopupModeStore(),
        sessionID: UUID = UUID(),
        registerStreamingTask: @escaping @MainActor (Task<Void, Never>?) -> Void = { _ in },
        onEnterSearch: @escaping @MainActor (CGRect?) -> Void = { _ in },
        onExitSearch: @escaping @MainActor () -> Void = {},
        onExitContent: @escaping @MainActor () -> Void = {},
        onDismissContent: (@MainActor () -> Void)? = nil,
        onCardDrag: (@MainActor (ResultCardDragPhase) -> Void)? = nil,
        onResize: (@MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void)? = nil,
        onPinCard: (@MainActor () -> Void)? = nil,
        onCardEffect: @escaping @MainActor (ActionResult) -> Void = { _ in },
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onContentSizeChange: (@MainActor (CGSize) -> Void)? = nil,
        onAIStateChange: (@MainActor (Bool, Bool) -> Void)? = nil,
        onAIResult: (@MainActor (String, Bool, String, Bool) -> Void)? = nil,
        onSubBarActiveChanged: (@MainActor (Bool) -> Void)? = nil,
        onRequestSubBarToggle: (@MainActor (any Action, Int, CGRect) -> Void)? = nil,
        onRequestSubBarDwell: (@MainActor (any Action, Int, CGRect) -> Void)? = nil,
        onCancelSubBarDwell: (@MainActor () -> Void)? = nil,
        onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)? = nil,
        onEnteredScopedSearch: (@MainActor (any Action, CGRect?) -> Void)? = nil,
        onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)? = nil,
        onActionPerformed: (@MainActor (String) -> Void)? = nil,
        onWillPerformAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool)? = nil,
        onRunLoadingAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void)? = nil,
        onRunAI: (@MainActor (String) -> Void)? = nil,
        onRunAIPrompt: (@MainActor (String, Bool, Bool) -> Void)? = nil,
        onSaveAIPrompt: (@MainActor (String, Bool) -> Void)? = nil,
        onFollowUp: (@MainActor (String) -> Void)? = nil,
        onCancelFollowUp: (@MainActor () -> Void)? = nil,
        onSubmitInstruction: (@MainActor (UUID, String) -> Void)? = nil,
        onCancelInstruction: (@MainActor () -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary },
        onShowTooltip: (@MainActor (String, CGRect, String, Bool) -> Void)? = nil,
        onHideTooltip: (@MainActor () -> Void)? = nil
    ) {
        _selectedTheme = Setting(SettingKey.popupTheme, store: settingsStore)
        _themeColor = Setting(SettingKey.popupThemeColor, store: settingsStore)
        _popupScale = Setting(SettingKey.popupScale, store: settingsStore)
        _pageSize = Setting(SettingKey.popupPageSize, store: settingsStore)
        _fitToWidth = Setting(SettingKey.popupFitToWidth, store: settingsStore)
        _showSearchAllActions = Setting(SettingKey.showSearchAllActions, store: settingsStore)
        _contextualActionsEnabled = Setting(SettingKey.contextualActionsEnabled, store: settingsStore)
        _disabledContextualIDs = Setting(SettingKey.disabledContextualActionIDs, store: settingsStore)
        _contextualPillPosition = Setting(SettingKey.contextualPillPosition, store: settingsStore)
        _popupAlignment = Setting(SettingKey.popupAlignment, store: settingsStore)
        _completionCopyToClipboard = Setting(SettingKey.completionCopyToClipboard, store: settingsStore)
        self.actions = actions
        self.allActions = allActions ?? actions
        self.context = context
        self.alternateSearchContext = alternateSearchContext
        self.onSearchContextChanged = onSearchContextChanged
        self.onResult = onResult
        self.onContentSizeChange = onContentSizeChange
        self.onAIStateChange = onAIStateChange
        self.onAIResult = onAIResult
        self.onSubBarActiveChanged = onSubBarActiveChanged
        self.onRequestSubBarToggle = onRequestSubBarToggle
        self.onRequestSubBarDwell = onRequestSubBarDwell
        self.onCancelSubBarDwell = onCancelSubBarDwell
        self.onExitContent = onExitContent
        self.onDismissContent = onDismissContent ?? onExitContent
        self.onCardDrag = onCardDrag
        self.onResize = onResize
        self.onPinCard = onPinCard
        self.onCardEffect = onCardEffect
        self.onHoveredActionChanged = onHoveredActionChanged
        self.onEnteredScopedSearch = onEnteredScopedSearch
        self.onPaginationAnchor = onPaginationAnchor
        self.onActionPerformed = onActionPerformed
        self.onWillPerformAction = onWillPerformAction
        self.onRunLoadingAction = onRunLoadingAction
        self.onRunAI = onRunAI
        self.onRunAIPrompt = onRunAIPrompt
        self.onSaveAIPrompt = onSaveAIPrompt
        self.onFollowUp = onFollowUp
        self.onCancelFollowUp = onCancelFollowUp
        self.onSubmitInstruction = onSubmitInstruction
        self.onCancelInstruction = onCancelInstruction
        self.onClickIntent = onClickIntent
        self.onShowTooltip = onShowTooltip
        self.onHideTooltip = onHideTooltip
        self.isStatic = isStatic
        self.screenWidth = screenWidth
        self.hoverState = hoverState
        self.presenter = presenter
        self.sessionID = sessionID
        self.registerStreamingTask = registerStreamingTask
        self._modeStore = ObservedObject(wrappedValue: modeStore)
        self.onEnterSearch = onEnterSearch
        self.onExitSearch = onExitSearch
        self._aiCardAboveBar = State(initialValue: initialAICardAboveBar)
        self._cachedCompletions = State(initialValue: Self.resolveCompletions(actions: actions, context: context))
    }

    /// Resolves the inline completion words once per show (the selection text never changes for the
    /// view's lifetime), so the bar can derive `hasCompletions`/`inCompletionMode` from a single
    /// cached value instead of re-running NSSpellChecker work on every body evaluation.
    @MainActor
    private static func resolveCompletions(actions: [any Action], context: ActionContext) -> [String] {
        guard let provider = actions.first(where: { $0 is any WordCompletionProviding }) as? any WordCompletionProviding,
              provider.isEnabled(for: context) else { return [] }
        return provider.fetchCompletions(for: context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasCompletions: Bool {
        return !cachedCompletions.isEmpty
    }

    private var inCompletionMode: Bool {
        return hasCompletions && isShowingCompletions
    }

    /// Bar rows: everything except the inline completion pseudo-action and any action that some
    /// `SubActionProviding` row resolves as a child (group sub-actions, AI presets). Membership is
    /// resolver/protocol-driven — the view never re-derives id-prefix conventions. A group row
    /// itself only appears when at least one of its sub-actions is applicable to the current
    /// context — with every sub-action disabled the parent would be an inert row. Paste-requiring
    /// actions (Paste/Cut) are dropped when the probe confirmed the target can't paste.
    var displayActions: [any Action] {
        let resolver = SubActionResolver()
        let subActionIDs = Set(
            actions.flatMap { parent in
                resolver.subActions(of: parent, in: actions).map(\.id)
            }
        )
        return actions.filter { action in
            guard !ActionIdentity.isCompletionPseudoAction(action) else { return false }
            if hiddenForPasteAvailability(action) { return false }
            if action.chrome.popupBehavior == .showSubActions || action.chrome.launchesAI {
                return isStatic || !resolver.subActions(of: action, in: actions).isEmpty
            }
            return !subActionIDs.contains(action.id)
        }
    }

    /// Paste/Cut can only perform when the target app supports paste; a confirmed cannot-paste
    /// probe hides them from the bar and the search palette (nil/unknown keeps them visible).
    private func hiddenForPasteAvailability(_ action: any Action) -> Bool {
        modeStore.canPaste == false && action is any PasteRequiringAction
    }

    private var maxBarBudget: CGFloat {
        PopupMetrics.maxBarWidth(for: screenWidth)
    }

    /// Matching prioritized contextual actions (e.g. Calculate for math, Open Link for URLs, Calendar for dates).
    private var contextualActions: [any Action] {
        guard contextualActionsEnabled else { return [] }
        return displayActions.filter { action in
            (isStatic || !disabledContextualIDs.contains(action.id)) && action.isContextual
        }
    }

    /// Remaining non-contextual actions shown in the standard actions island.
    private var standardActions: [any Action] {
        if contextualActions.isEmpty {
            return displayActions
        }
        return displayActions.filter { action in
            (!isStatic && disabledContextualIDs.contains(action.id)) || !action.isContextual
        }
    }

    private var pages: [[any Action]] {
        let leadingWidth = hasCompletions ? (chevronWidth) : 0
        let trailingWidth = showSearchAllActions ? buttonWidth : 0
        // Reads `inlineResults` so a preview arriving re-packs the page at the button's real width
        // instead of overflowing the budget (the published dictionary already drives a re-render).
        return PopupPageLayout.computePages(
            actions: standardActions,
            inlineResults: modeStore.inlineResults,
            leadingWidth: leadingWidth,
            trailingWidth: trailingWidth,
            // The contextual island has its own width and does not consume main-bar slots.
            maxBudget: maxBarBudget,
            maxItemsPerPage: fitToWidth ? Int.max : max(2, min(24, pageSize)),
            scale: scale,
            presenter: presenter
        )
    }

    private var totalPages: Int {
        max(1, pages.count)
    }

    private var pagedStandardActions: [any Action] {
        let p = pages
        let clamped = max(0, min(currentPage, p.count - 1))
        guard clamped < p.count else { return [] }
        return p[clamped]
    }

    /// True when the contextual island is drawn after (to the right of) the standard island.
    private var contextualIslandTrailing: Bool {
        let position = ContextualPillPosition(rawValue: contextualPillPosition) ?? .auto
        return position.isTrailing(for: PopupBarAlignment(rawValue: popupAlignment) ?? .left)
    }

    /// Bar actions in left-to-right order; `.action(index)` hover targets index into this list.
    private var visibleBarActions: [any Action] {
        contextualIslandTrailing ? pagedStandardActions + contextualActions : contextualActions + pagedStandardActions
    }

    private var hasLeftChevron: Bool { currentPage > 0 }
    private var hasRightChevron: Bool { currentPage < totalPages - 1 }

    public var body: some View {
        barContent
            // Transparent ring that hosts the SwiftUI drop shadow inside the panel frame. Must
            // equal PopupMetrics.popupShadowInset — PopupPanel.ContentView excludes exactly this
            // region from mouse hit-testing so shadow clicks fall through to the app below.
            .padding(PopupMetrics.popupShadowInset)
            .coordinateSpace(name: "popupHoverSpace")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PopupContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
                MainActor.assumeIsolated {
                    hoverFrames = frames
                    updateHoveredTarget(for: hoverState.location)
                }
            }
            .onPreferenceChange(PopupContentSizePreferenceKey.self) { size in
                MainActor.assumeIsolated {
                    guard size.width > 0, size.height > 0 else { return }
                    onContentSizeChange?(size)
                }
            }
            .onReceive(hoverState.$location) { location in
                updateHoveredTarget(for: location)
            }
            .onChange(of: hoveredTarget) { _, newTarget in
                updateTooltip(for: newTarget)
            }
            .onChange(of: modeStore.mode) { _, newMode in
                if newMode != .actions {
                    tooltipPresenter.reset { onHideTooltip?() }
                    onCancelSubBarDwell?()
                }
            }
            .onChange(of: modeStore.isSubBarActive) { _, isActive in
                onSubBarActiveChanged?(isActive)
            }
            .onChange(of: totalPages) { _, count in
                // Re-packing (e.g. a preview landing and widening a button) can shrink the page
                // count; without this a stale `currentPage` would sit past the last page with a
                // dead chevron and an empty-looking page.
                if currentPage > count - 1 { currentPage = max(0, count - 1) }
            }
            .onChange(of: isProcessingAI) { _, active in
                onAIStateChange?(active, aiCardAboveBar)
            }
            .onDisappear {
                tooltipPresenter.reset { onHideTooltip?() }
                cancelAITask()
                onCancelSubBarDwell?()
            }
    }

    // MARK: - Unified Bar Container

    @ViewBuilder
    private var barContent: some View {
        if modeStore.mode == .content {
            resultCard
        } else if modeStore.mode == .instruction {
            instructionCard
        } else if modeStore.mode == .search {
            searchCard
        } else {
            mainBarStyled
        }
    }

    /// The result card: renders the native ResultCardView inline on the popup panel in place
    /// of the bar (content mode). Paste/Copy are explicit user requests routed through
    /// onCardEffect (bypassing the paste-vs-copy re-decision) that both dismiss the popup; the
    /// Paste button is hidden when the target app can't paste; the back chevron collapses back to
    /// the bar and Esc closes the card outright.
    @ViewBuilder
    private var resultCard: some View {
        if let payload = modeStore.resultCard {
            ResultCardView(
                payload: payload,
                canPaste: modeStore.canPaste,
                maxSize: modeStore.resultCardSize,
                isUserSized: modeStore.isSurfaceUserSized,
                isPinned: modeStore.isCardPinned,
                onExit: { onExitContent() },
                onPaste: {
                    if let file = payload.file {
                        onCardEffect(.saveFile(file.url))
                    } else {
                        onCardEffect(.paste(payload.text))
                    }
                },
                onCopy: {
                    if let file = payload.file {
                        onCardEffect(.copyFile(file.url))
                    } else {
                        onCardEffect(.copy(payload.text))
                    }
                },
                onSave: {
                    if let file = payload.file {
                        onCardEffect(.saveFile(file.url))
                    }
                },
                onDrag: { phase in onCardDrag?(phase) },
                onResize: { edge, phase in onResize?(edge, phase) },
                onPin: { onPinCard?() },
                onFollowUp: onFollowUp.map { run in { instruction in run(instruction) } },
                onCancelFollowUp: onCancelFollowUp
            )
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
        }
    }


    /// The additional-instruction prompt (instruction mode): collects a one-time instruction for
    /// an AI preset that asks for one, before anything is sent to the provider.
    @ViewBuilder
    private var instructionCard: some View {
        if let request = modeStore.instructionRequest {
            AdditionalInstructionCardView(
                request: request,
                onSubmit: { instruction in onSubmitInstruction?(request.id, instruction) },
                onCancel: { onCancelInstruction?() },
                onDrag: { phase in onCardDrag?(phase) }
            )
            // A new request (same preset run again) starts from an empty field.
            .id(request.id)
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
        }
    }

    @ViewBuilder
    private var mainBarStyled: some View {
        if inCompletionMode {
            completionHStack
                .popupCardChrome(
                    cornerRadius: cornerRadius,
                    effectiveTheme: effectiveTheme,
                    colorScheme: effectiveColorScheme
                )
                .environment(\.colorScheme, effectiveColorScheme)
        } else if contextualActions.isEmpty {
            standardIsland
                .overlay(processingGlowBorder)
                .environment(\.colorScheme, effectiveColorScheme)
        } else {
            HStack(spacing: islandGap) {
                if contextualIslandTrailing {
                    standardIsland
                        .overlay(processingGlowBorder)
                    contextualIsland
                } else {
                    contextualIsland
                    standardIsland
                        .overlay(processingGlowBorder)
                }
            }
            .environment(\.colorScheme, effectiveColorScheme)
        }
    }

    @ViewBuilder
    private var processingGlowBorder: some View {
        if isProcessingAI {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.blue.opacity(0.3),
                            Color.blue,
                            Color.cyan,
                            Color.blue,
                            Color.blue.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: glowOffset, y: 0.5),
                        endPoint: UnitPoint(x: glowOffset + 1.2, y: 0.5)
                    ),
                    lineWidth: 2.0
                )
                .shadow(color: Color.blue.opacity(0.8), radius: 6, x: 0, y: 0)
                .onAppear {
                    glowOffset = -1.0
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        glowOffset = 1.0
                    }
                }
        }
    }

    /// The action-search palette: renders PopupSearchView with dedicated card chrome matching
    /// ResultCardView in content mode.
    @ViewBuilder
    private var searchCard: some View {
        PopupSearchView(
            catalog: searchCatalog,
            context: context,
            alternateContext: alternateSearchContext,
            onContextChanged: onSearchContextChanged,
            resultsAbove: false,
            presenter: presenter,
            modeStore: modeStore,
            scope: modeStore.scope,
            usageRecency: ActionUsageStore.shared.recency,
            onResult: onResult,
            onExit: onExitSearch,
            onDrag: { phase in onCardDrag?(phase) },
            onExitScope: {
                modeStore.scope = nil
                onExitSearch()
            },
            onRunAI: { actionID in
                runAIAction(actionID)
            },
            onRunAIPrompt: { instruction, replace, includeContext in
                if let onRunAIPrompt {
                    // Same contract as onRunAI: the controller's flow snapshots the selection and
                    // dismisses the popup itself, so the palette must not exit first.
                    onRunAIPrompt(instruction, replace, includeContext)
                } else {
                    // Preview/static fallback: no in-place delivery here, always the card.
                    onExitSearch()
                    let taskPrompt = includeContext
                        ? PaletteAIPrompt.askAITaskPrompt(for: instruction)
                        : PaletteAIPrompt.standaloneQuestionPrompt(for: instruction)
                    runAIPreset(prompt: taskPrompt, title: PaletteAIPrompt.toolTitle(for: instruction))
                }
            },
            onSaveAIPrompt: { instruction, replace in
                if let onSaveAIPrompt {
                    onSaveAIPrompt(instruction, replace)
                } else {
                    onExitSearch()
                    var preset = aiManager.preset(matchingPrompt: instruction)
                        ?? aiManager.addCustomPreset(title: PaletteAIPrompt.toolTitle(for: instruction), prompt: instruction)
                    runAIPreset(
                        prompt: PaletteAIPrompt.saveToolTaskPrompt(for: instruction),
                        title: preset.title,
                        onGeneratedTitle: { cleanTitle in
                            preset.title = cleanTitle
                            aiManager.updatePreset(preset)
                        }
                    )
                }
            },
            onActionPerformed: onActionPerformed,
            onWillPerformAction: onWillPerformAction,
            onRunLoadingAction: onRunLoadingAction,
            onClickIntent: onClickIntent
        )
        .environment(\.colorScheme, effectiveColorScheme)
        .environment(\.popupEffectiveTheme, effectiveTheme)
    }

    /// The search palette's catalog: the coordinator's search catalog minus Paste-requiring
    /// actions hidden by a confirmed cannot-paste probe.
    private var searchCatalog: [any Action] {
        ActionCoordinator.shared.searchCatalog(for: context)
            .filter { !hiddenForPasteAvailability($0) }
    }

    // MARK: - AI Helpers

    /// Shared by standalone bar buttons and palette rows. The controller must snapshot the
    /// selection before dismissing the popup, including when search was opened by a hotkey.
    func runAIAction(_ actionID: String) {
        onActionPerformed?(actionID)
        if let onRunAI {
            onRunAI(actionID)
        } else {
            if modeStore.mode == .search { onExitSearch() }
            guard let preset = aiManager.preset(forActionID: actionID) else { return }
            runAIPreset(prompt: aiManager.promptForPreset(preset), title: preset.title)
        }
    }

    private func runAIPreset(prompt: String, title: String, onGeneratedTitle: ((String) -> Void)? = nil) {
        cancelAITask()

        let selectionText = context.selection.text
        let task = Task { @MainActor in
            isProcessingAI = true
            modeStore.isProcessingAI = true
            defer {
                // Clear the controller's registration only on natural completion. When this
                // task ends because hide()/show(for:) cancelled it, they already nil'd the
                // registration — an unconditional clear here lets this stale task unwinding
                // late wipe a newer session's live registration, so its hide() would never
                // cancel the still-running stream.
                if !Task.isCancelled {
                    registerStreamingTask(nil)
                    isProcessingAI = false
                    modeStore.isProcessingAI = false
                }
            }

            do {
                let provider = aiManager.currentProvider

                var accumulated = ""
                var hasYielded = false
                var activeTitle = title

                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled else { return }
                    accumulated += chunk
                    if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                        activeTitle = generated
                        onGeneratedTitle?(generated)
                    }
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        hasYielded = true
                        onAIResult?(cleaned, false, activeTitle, true)
                    }
                }

                guard !Task.isCancelled else { return }
                if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                    activeTitle = generated
                    onGeneratedTitle?(generated)
                }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    if !hasYielded {
                        throw AIError.invalidResponse
                    }
                } else {
                    onAIResult?(finalResponse, false, activeTitle, false)
                }
            } catch is CancellationError {
                // no-op
            } catch let error as AIError where error == .cancelled {
                // no-op
            } catch let error as URLError where error.code == .cancelled {
                // no-op
            } catch {
                guard !Task.isCancelled else { return }
                Log.ai.error("AI preset execution failed in PopupView: \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                onAIResult?(message, true, title, false)
            }
        }
        aiTask = task
        // Register with the controller so hide() cancels the stream immediately instead of
        // waiting for SwiftUI teardown — chunks must never outlive their session.
        registerStreamingTask(task)
    }

    private func cancelAITask() {
        aiTask?.cancel()
        aiTask = nil
        isProcessingAI = false
        modeStore.isProcessingAI = false
    }

    // MARK: - Completion Mode Bar Layout

    private var completionHStack: some View {
        HStack(spacing: 0) {
            // Far Left: Up Arrow button toggles to normal actions mode
            chevronButton(systemImage: "chevron.up", label: "Back to actions") {
                onPaginationAnchor?(.left)
                isShowingCompletions = false
            }
            
            // Horizontal Completion Word Items
            let list = cachedCompletions
            ForEach(Array(list.enumerated()), id: \.offset) { index, word in
                let isHovered = hoveredTarget == .completion(index)
                completionButton(word: word, index: index, isHovered: isHovered)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Normal Actions Bar Layout

    private var contextualIsland: some View {
        HStack(spacing: 0) {
            ForEach(Array(contextualActions.enumerated()), id: \.element.id) { offset, action in
                let index = contextualIslandTrailing ? pagedStandardActions.count + offset : offset
                let isDirectlyHovered = hoveredTarget == .action(index)
                let isActiveParent = modeStore.activeSubGroupID == action.id && !isDirectlyHovered
                actionButton(action: action, index: index, isHovered: isDirectlyHovered, isActiveParent: isActiveParent, leadingEdge: offset == 0, trailingEdge: offset == contextualActions.count - 1)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .popupCardChrome(
            cornerRadius: cornerRadius,
            effectiveTheme: effectiveTheme,
            colorScheme: effectiveColorScheme
        )
    }

    private var standardIsland: some View {
        HStack(spacing: 0) {
            // Completion toggle lives on the far left; both pagination chevrons sit together on the
            // right (just before the command affordance) so next/previous are easy to reach.
            if hasCompletions {
                chevronButton(systemImage: "chevron.down", label: "Show completions") {
                    onPaginationAnchor?(.left)
                    isShowingCompletions = true
                }
            }

            ForEach(Array(pagedStandardActions.enumerated()), id: \.element.id) { offset, action in
                let index = contextualIslandTrailing ? offset : contextualActions.count + offset
                let isDirectlyHovered = hoveredTarget == .action(index)
                let isActiveParent = modeStore.activeSubGroupID == action.id && !isDirectlyHovered
                actionButton(action: action, index: index, isHovered: isDirectlyHovered, isActiveParent: isActiveParent, leadingEdge: offset == 0 && !hasCompletions, trailingEdge: offset == pagedStandardActions.count - 1 && !hasLeftChevron && !hasRightChevron && !showSearchAllActions)
            }

            // Sparkles AI launcher is a normal action row (chrome.launchesAI); it paginates with
            // the other actions and its click opens AI mode via the branch in actionButton.

            if hasLeftChevron {
                chevronButton(systemImage: "chevron.left", label: "Previous page") {
                    onPaginationAnchor?(.right)
                    currentPage -= 1
                }
            }
            if hasRightChevron {
                chevronButton(systemImage: "chevron.right", label: "Next page") {
                    onPaginationAnchor?(.right)
                    currentPage += 1
                }
            }

            // Action-search affordance: command glyph. Kept outside
            // the paged actions so it always sits at the far-right edge on every page.
            if showSearchAllActions {
                let isHovered = hoveredTarget == .search
                let affordanceForeground: Color = isHovered ? .white : PopupThemeModel.restForeground(for: effectiveTheme)
                Button {
                    let frame = hoverFrames[.search]
                    onEnterSearch(frame)
                } label: {
                    Image(systemName: "command")
                        .font(.system(size: 15 * scale, weight: .regular))
                        .foregroundColor(affordanceForeground)
                        .frame(width: buttonWidth, height: barButtonHeight)
                        .popupBarHighlight(isHovered ? PopupThemeModel.barHoverFill : .clear, scale: scale, trailingEdge: true, isHovered: isHovered, namespace: hoverHighlightNamespace)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search all actions")
                .popupHoverTarget(.search)
                .onHover { isHovering in
                    useLocalHoverFallback(for: .search, isHovering: isHovering)
                }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .popupCardChrome(
            cornerRadius: cornerRadius,
            effectiveTheme: effectiveTheme,
            colorScheme: effectiveColorScheme
        )
    }

    // MARK: - Completion Button

    @ViewBuilder
    private func completionButton(word: String, index: Int, isHovered: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)

        Button {
            onResult(.paste(word))
        } label: {
            Text(word)
                .font(.system(size: 15 * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(maxWidth: 177 * scale)
                .padding(.horizontal, 12.5 * scale)
                .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                .popupBarHighlight(isHovered ? PopupThemeModel.barHoverFill : .clear, scale: scale, isText: true, trailingEdge: index == cachedCompletions.count - 1, isHovered: isHovered, namespace: hoverHighlightNamespace)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word)
        .popupHoverTarget(.completion(index))
        .onHover { isHovering in
            useLocalHoverFallback(for: .completion(index), isHovering: isHovering)
        }
    }

    // MARK: - Unified Action Button

    @ViewBuilder
    private func actionButton(action: any Action, index: Int, isHovered: Bool, isActiveParent: Bool = false, leadingEdge: Bool = false, trailingEdge: Bool = false) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)

        let backgroundColor: Color = {
            if isHovered {
                return PopupThemeModel.barHoverFill
            } else if isActiveParent {
                return effectiveColorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
            } else {
                return Color.clear
            }
        }()

        let foregroundColor: Color = isHovered ? .white : restForeground

        let isGroup = action.gesturePolicy.singleClick == .openSubActions || action.chrome.launchesAI
        let subBarAbove = modeStore.subBarAbove

        let labelView = Group {
            if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                Text(resolved)
                    .font(.system(size: 15 * scale, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foregroundColor)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .popupBarHighlight(backgroundColor, scale: scale, isText: true, leadingEdge: leadingEdge, trailingEdge: trailingEdge, isHovered: isHovered, namespace: hoverHighlightNamespace)
                    .transition(.opacity)
            } else {
                iconView(for: action.displayIcon(using: presenter))
                    .foregroundColor(foregroundColor)
                    .padding(.horizontal, {
                        if case .text = action.displayIcon(using: presenter) { return 7.0 * scale }
                        return 0.0
                    }())
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .popupBarHighlight(backgroundColor, scale: scale, isText: { if case .text = action.displayIcon(using: presenter) { return true }; return false }(), leadingEdge: leadingEdge, trailingEdge: trailingEdge, isHovered: isHovered, namespace: hoverHighlightNamespace)
                    .overlay(alignment: subBarAbove ? .top : .bottom) {
                        // The triangle marks a group button only while its sub-bar is closed and
                        // the button itself isn't hovered; hover and the open bar already show it.
                        if isGroup && !isHovered && modeStore.activeSubGroupID != action.id {
                            GroupIndicatorTriangle(pointingUp: subBarAbove)
                                .fill(foregroundColor.opacity(0.65))
                                .frame(width: 4.6 * scale, height: 2.9 * scale)
                                .padding(subBarAbove ? .top : .bottom, 2.1 * scale)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())

        Group {
            switch action.gesturePolicy.singleClick {
            case .openSubActions:
                // Group rows open scoped search palette on click; sub-bar opens on hover dwell
                Button {
                    onCancelSubBarDwell?()
                    let frame = hoverFrames[.action(index)]
                    onEnteredScopedSearch?(action, frame)
                } label: {
                    labelView
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel({
                        let title = action.displayTitle(using: presenter)
                        if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                            return "\(title): \(resolved)"
                        }
                        return title
                    }())
                    .popupHoverTarget(.action(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                }
            case .perform:
                if action.chrome.launchesAI {
                    // AI Tools launcher opens scoped search palette on click; sub-bar opens on hover dwell
                    Button {
                        guard action.isEnabled(for: context) else { return }
                        onCancelSubBarDwell?()
                        let frame = hoverFrames[.action(index)]
                        onEnteredScopedSearch?(action, frame)
                    } label: {
                        labelView
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.displayTitle(using: presenter))
                    .popupHoverTarget(.action(index))
                    .onHover { isHovering in
                        useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                    }
                } else {
                    // Leaf actions use their existing execution flow.
                    Button {
                        onCancelSubBarDwell?()
                        if ActionIdentity.isAIPreset(action) {
                            runAIAction(action.id)
                            return
                        }
                        // Capture the click intent once, synchronously, so the perform context and
                        // the delivery snapshot agree and neither reads live state after an await.
                        let clickIntent = onClickIntent()
                        if action.chrome.showsLoading {
                            onRunLoadingAction?(action, clickIntent)
                            return
                        }
                        guard onWillPerformAction?(action, clickIntent) ?? true else { return }
                        onActionPerformed?(action.id)
                        if action.chrome.isInlineResult {
                            if let resolved = modeStore.inlineResults[action.id] {
                                onResult(.text(resolved))
                                return
                            } else if let inFlight = InlineResultEvaluator.shared.runningTask(for: action.id) {
                                Task {
                                    do {
                                        if let text = await inFlight.value, !text.isEmpty {
                                            onResult(.text(text))
                                            return
                                        }
                                        let match = action.matchInfo(for: context)
                                        let performContext = ActionContext(
                                            selection: context.selection,
                                            modifiers: context.modifiers,
                                            isSecondaryClick: clickIntent == .secondary,
                                            match: match
                                        )
                                        let result = try await action.perform(performContext)
                                        onResult(result)
                                    } catch {
                                        Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                                        onResult(.toast(StatusFeedback(error: error)))
                                    }
                                }
                                return
                            }
                        }
                        Task {
                            do {
                                let match = action.matchInfo(for: context)
                                let performContext = ActionContext(
                                    selection: context.selection,
                                    modifiers: context.modifiers,
                                    isSecondaryClick: clickIntent == .secondary,
                                    match: match
                                )
                                let result = try await action.perform(performContext)
                                onResult(result)
                            } catch {
                                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                                onResult(.toast(StatusFeedback(error: error)))
                            }
                        }
                    } label: {
                        labelView
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel({
                        let title = action.displayTitle(using: presenter)
                        if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                            return "\(title): \(resolved)"
                        }
                        return title
                    }())
                    .popupHoverTarget(.action(index))
                    .onHover { isHovering in
                        useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                    }
                }
            }
        }
        .animation(PopupMetrics.inlineSpring, value: modeStore.inlineResults[action.id])
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        // Each chevron gets its own hover target keyed by its glyph, so hovering the
        // pagination right/left chevrons never highlights the completion-mode up chevron
        // (or the completion toggle) and vice-versa.
        let target: PopupHoverTarget = .chevron(systemImage)
        let isHovered = hoveredTarget == target
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundColor(isHovered ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                .frame(width: chevronWidth, height: barButtonHeight)
                .popupBarHighlight(isHovered ? PopupThemeModel.barHoverFill : .clear, scale: scale, leadingEdge: systemImage == "chevron.up" || systemImage == "chevron.down", trailingEdge: !showSearchAllActions && (systemImage == "chevron.right" || (systemImage == "chevron.left" && !hasRightChevron)), isHovered: isHovered, namespace: hoverHighlightNamespace)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popupHoverTarget(target)
        .onHover { isHovering in
            useLocalHoverFallback(for: target, isHovering: isHovering)
        }
    }

    private func updateHoveredTarget(for location: CGPoint?) {
        guard !isStatic else { return }
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        setHoveredTarget(target)
    }

    /// Both cursor tracking and the local fallback use target transitions to own dwell timing.
    /// Repeated entries and stale exits must not restart or cancel another target's timer.
    private func setHoveredTarget(_ target: PopupHoverTarget?) {
        guard target != hoveredTarget else { return }
        let oldTarget = hoveredTarget
        hoveredTarget = target
        reportHoveredAction()

        if case .action(let index) = target, index < visibleBarActions.count {
            let action = visibleBarActions[index]
            let isGroup = action.gesturePolicy.singleClick == .openSubActions || action.chrome.launchesAI
            if isGroup {
                let frame = hoverFrames[.action(index)] ?? .zero
                onRequestSubBarDwell?(action, index, frame)
            } else if case .action = oldTarget {
                onCancelSubBarDwell?()
            }
        } else if case .action = oldTarget {
            onCancelSubBarDwell?()
        }
    }

    /// Maps the current hoveredTarget to its action (if any) and reports it upward so the
    /// controller can track the hovered row (right-click path).
    private func reportHoveredAction() {
        let action: (any Action)? = {
            if inCompletionMode, case .completion(let index) = hoveredTarget, index < cachedCompletions.count {
                return WordCompletionCandidateAction(word: cachedCompletions[index])
            }
            guard case .action(let index) = hoveredTarget, index < visibleBarActions.count else { return nil }
            return visibleBarActions[index]
        }()
        onHoveredActionChanged?(action)
    }

    func useLocalHoverFallback(for target: PopupHoverTarget, isHovering: Bool) {
        // The location-driven path owns highlights AND dwell when tracking is available.
        // SwiftUI can emit an exit during highlight relayout while the cursor is still here.
        guard !isStatic, !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            setHoveredTarget(target)
        } else if hoveredTarget == target {
            setHoveredTarget(nil)
        }
    }

    // MARK: - Tooltip Management

    private func tooltipText(for target: PopupHoverTarget) -> String? {
        switch target {
        case .action(let index):
            guard index < visibleBarActions.count else { return nil }
            return visibleBarActions[index].displayTitle(using: presenter)
        case .subAction:
            return nil
        case .search:
            return String(localized: "Search all actions")
        case .chevron(let glyph):
            switch glyph {
            case "chevron.left", "chevron.left.sub": return String(localized: "Previous page")
            case "chevron.right", "chevron.right.sub": return String(localized: "Next page")
            case "chevron.down": return String(localized: "Show completions")
            case "chevron.up": return String(localized: "Back to actions")
            default: return glyph
            }
        case .completion(let index):
            guard index < cachedCompletions.count else { return nil }
            return cachedCompletions[index]
        }
    }

    private func updateTooltip(for target: PopupHoverTarget?) {
        let resolved: (text: String, frame: CGRect)? = {
            guard !isStatic, modeStore.mode == .actions, let target,
                  let text = tooltipText(for: target), let targetFrame = hoverFrames[target] else { return nil }
            return (text, targetFrame)
        }()
        tooltipPresenter.update(
            text: resolved?.text,
            show: { [onShowTooltip, effectiveTheme, isDark = effectiveColorScheme == .dark] in
                guard let resolved else { return }
                onShowTooltip?(resolved.text, resolved.frame, effectiveTheme, isDark)
            },
            hide: { [onHideTooltip] in
                onHideTooltip?()
            }
        )
    }

    // MARK: - Icon Helper
 
    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        ActionIconView(icon: icon, size: 15.5, scale: scale)
    }
}

/// A lightweight synthetic action representing an inline word completion candidate so the
/// right-click force-copy path can execute and deliver it identically to other bar items.
private struct WordCompletionCandidateAction: Action {
    let word: String
    var id: String { "builtin.completion.\(word)" }
    var title: String { word }
    var icon: ActionIcon { .text(word) }
    var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, requiresLiveSelection: true)
    }

    @MainActor
    func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult {
        return .paste(word)
    }
}

/// A compact custom triangle shape used as a subtle group sub-bar indicator.
private struct GroupIndicatorTriangle: Shape {
    var pointingUp: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
