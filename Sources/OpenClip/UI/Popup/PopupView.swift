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
    /// Called as the result card's header handle is dragged, so the controller can move the panel.
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
    /// snapshot the action's declared delivery for the paste-vs-copy decision.
    public let onWillPerformAction: (@MainActor (any Action) -> Void)?
    /// Called when a `showsLoading` bar action is clicked: the controller early-closes the popup
    /// and runs the action via the loading toast flow instead of the inline perform path.
    public let onRunLoadingAction: (@MainActor (any Action) -> Void)?
    /// Called when an AI preset action is run: the controller closes the popup and runs via the loading toast flow.
    public let onRunAI: (@MainActor (String) -> Void)?
    /// Runs the palette's typed query as a one-off AI instruction (the empty state's "Ask AI"
    /// row). nil falls back to the view's own streaming flow (preview/static hosts).
    public let onRunAIPrompt: (@MainActor (String) -> Void)?
    /// Saves the palette's typed query as a reusable AI tool and runs it (the empty state's
    /// "Save as AI tool" row). nil falls back to the view's own flow.
    public let onSaveAIPrompt: (@MainActor (String) -> Void)?
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
    private let isStatic: Bool

    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @AppStorage(SettingKey.popupScale.name) private var popupScale: Int = SettingKey.popupScale.defaultValue
    @AppStorage(SettingKey.popupBarWidth.name) private var barWidthLevel: Int = SettingKey.popupBarWidth.defaultValue
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
    
    @AppStorage(SettingKey.completionCopyToClipboard.name) private var completionCopyToClipboard: Bool = SettingKey.completionCopyToClipboard.defaultValue
    
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
    private var buttonWidth: CGFloat { PopupMetrics.actionButtonWidth * scale }
    private var chevronWidth: CGFloat { 29 * scale }
    private var barButtonHeight: CGFloat { PopupMetrics.barButtonHeight * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    @MainActor
    public init(
        actions: [any Action],
        allActions: [any Action]? = nil,
        context: ActionContext,
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
        onWillPerformAction: (@MainActor (any Action) -> Void)? = nil,
        onRunLoadingAction: (@MainActor (any Action) -> Void)? = nil,
        onRunAI: (@MainActor (String) -> Void)? = nil,
        onRunAIPrompt: (@MainActor (String) -> Void)? = nil,
        onSaveAIPrompt: (@MainActor (String) -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary },
        onShowTooltip: (@MainActor (String, CGRect, String, Bool) -> Void)? = nil,
        onHideTooltip: (@MainActor () -> Void)? = nil
    ) {
        self.actions = actions
        self.allActions = allActions ?? actions
        self.context = context
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
        self.onClickIntent = onClickIntent
        self.onShowTooltip = onShowTooltip
        self.onHideTooltip = onHideTooltip
        self.isStatic = isStatic
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
    private var displayActions: [any Action] {
        let resolver = SubActionResolver()
        let subActionIDs = Set(
            actions.flatMap { parent in
                resolver.subActions(of: parent, in: actions).map(\.id)
            }
        )
        return actions.filter { action in
            guard !ActionIdentity.isCompletionPseudoAction(action) else { return false }
            if hiddenForPasteAvailability(action) { return false }
            if action.chrome.popupBehavior == .showSubActions {
                return !resolver.subActions(of: action, in: actions).isEmpty
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
        PopupMetrics.barWidth(for: barWidthLevel) * scale
    }

    private var pages: [[any Action]] {
        let leadingWidth = hasCompletions ? (chevronWidth) : 0
        let trailingWidth = buttonWidth // search button
        return PopupPageLayout.computePages(
            actions: displayActions,
            leadingWidth: leadingWidth,
            trailingWidth: trailingWidth,
            maxBudget: maxBarBudget,
            scale: scale,
            presenter: presenter
        )
    }

    private var totalPages: Int {
        max(1, pages.count)
    }

    private var pagedActions: [any Action] {
        let p = pages
        let clamped = max(0, min(currentPage, p.count - 1))
        guard clamped < p.count else { return [] }
        return p[clamped]
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
                onDismiss: { onDismissContent() },
                onPaste: { onCardEffect(.paste(payload.text)) },
                onCopy: { onCardEffect(.copy(payload.text)) },
                onDrag: { phase in onCardDrag?(phase) },
                onResize: { edge, phase in onResize?(edge, phase) },
                onPin: { onPinCard?() }
            )
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
        }
    }


    @ViewBuilder
    private var mainBarStyled: some View {
        let styledBar = Group {
            if effectiveTheme == "glass" {
                barStack
                    .layeredGlassSurface(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
            } else {
                barStack
                    .background(opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: Color.black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 6, x: 0, y: 3)
            }
        }

        styledBar
            .environment(\.colorScheme, effectiveColorScheme)
            .overlay(processingGlowBorder)
    }

    /// The themed bar content.
    @ViewBuilder
    private var barStack: some View {
        unifiedHStack
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

    // MARK: - Unified HStack Layout

    @ViewBuilder
    private var unifiedHStack: some View {
        if inCompletionMode {
            completionHStack
        } else {
            actionsStack
        }
    }

    /// The plain actions bar — the hover preview strip is gone with the canvas feature, so the bar
    /// is just the actions HStack (paged actions + pagination + search affordance).
    @ViewBuilder
    private var actionsStack: some View {
        actionsHStack
    }

    /// The action-search palette: renders PopupSearchView with dedicated card chrome matching
    /// ResultCardView in content mode.
    @ViewBuilder
    private var searchCard: some View {
        PopupSearchView(
            catalog: searchCatalog,
            context: context,
            resultsAbove: false,
            presenter: presenter,
            modeStore: modeStore,
            scope: modeStore.scope,
            usageRecency: ActionUsageStore.shared.recency,
            maxSize: modeStore.searchPaletteSize,
            isUserSized: modeStore.isSurfaceUserSized,
            onResize: { edge, phase in onResize?(edge, phase) },
            onResult: onResult,
            onExit: onExitSearch,
            onExitScope: {
                modeStore.scope = nil
                onExitSearch()
            },
            onRunAI: { actionID in
                onActionPerformed?(actionID)
                if let onRunAI {
                    // Run first: the controller's AI flow snapshots the selection and dismisses
                    // the popup itself. Exiting search beforehand dismissed it *for* a palette
                    // opened straight from the hotkey (`openedDirectlyInSearch` → `hide()`),
                    // which cleared `currentActionContext` — so the preset never ran and only
                    // logged "Cannot run AI preset". From the bar the same exit merely returned
                    // to the bar, which is why AI worked there and nowhere else.
                    onRunAI(actionID)
                } else {
                    // Preview/static fallback: no controller flow to dismiss anything, so the
                    // palette closes itself before streaming into the card.
                    onExitSearch()
                    guard let preset = aiManager.preset(forActionID: actionID) else { return }
                    runAIPreset(prompt: aiManager.promptForPreset(preset), title: preset.title)
                }
            },
            onRunAIPrompt: { instruction in
                if let onRunAIPrompt {
                    // Same contract as onRunAI: the controller's flow snapshots the selection and
                    // dismisses the popup itself, so the palette must not exit first.
                    onRunAIPrompt(instruction)
                } else {
                    onExitSearch()
                    runAIPreset(prompt: instruction, title: PaletteAIPrompt.toolTitle(for: instruction))
                }
            },
            onSaveAIPrompt: { instruction in
                if let onSaveAIPrompt {
                    onSaveAIPrompt(instruction)
                } else {
                    onExitSearch()
                    let preset = aiManager.preset(matchingPrompt: instruction)
                        ?? aiManager.addCustomPreset(title: PaletteAIPrompt.toolTitle(for: instruction), prompt: instruction)
                    runAIPreset(prompt: preset.prompt, title: preset.title)
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

    private func runAIPreset(prompt: String, title: String) {
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
                if provider.type == .browser {
                    _ = try await provider.process(prompt: prompt, text: selectionText)
                    guard !Task.isCancelled else { return }
                    onResult(.success)
                    return
                }

                var accumulated = ""
                var hasYielded = false

                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled else { return }
                    accumulated += chunk
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        hasYielded = true
                        onAIResult?(cleaned, false, title, true)
                    }
                }

                guard !Task.isCancelled else { return }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    if !hasYielded {
                        throw AIError.invalidResponse
                    }
                } else {
                    onAIResult?(finalResponse, false, title, false)
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

    private var actionsHStack: some View {
        HStack(spacing: 0) {
            // Completion toggle lives on the far left; both pagination chevrons sit together on the
            // right (just before the command affordance) so next/previous are easy to reach.
            if hasCompletions {
                chevronButton(systemImage: "chevron.down", label: "Show completions") {
                    onPaginationAnchor?(.left)
                    isShowingCompletions = true
                }
            }

            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isDirectlyHovered = hoveredTarget == .action(index)
                let isActiveParent = modeStore.activeSubGroupID == action.id && !isDirectlyHovered
                actionButton(action: action, index: index, isHovered: isDirectlyHovered, isActiveParent: isActiveParent)
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
            let isHovered = hoveredTarget == .search
            let affordanceForeground = PopupThemeModel.restForeground(for: effectiveTheme)
            Button {
                let frame = hoverFrames[.search]
                onEnterSearch(frame)
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 13 * scale, weight: .regular))
                    .foregroundColor(isHovered ? .white : affordanceForeground)
                    .frame(width: buttonWidth, height: barButtonHeight)
                    .background(isHovered ? Color.accentColor : Color.clear)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search all actions")
            .popupHoverTarget(.search)
            .onHover { isHovering in
                useLocalHoverFallback(for: .search, isHovering: isHovering)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Completion Button

    @ViewBuilder
    private func completionButton(word: String, index: Int, isHovered: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)

        Button {
            onResult(.paste(word))
        } label: {
            Text(word)
                .font(.system(size: 13 * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(maxWidth: 154 * scale)
                .padding(.horizontal, 11 * scale)
                .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                .background(isHovered ? Color.accentColor : Color.clear)
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
    private func actionButton(action: any Action, index: Int, isHovered: Bool, isActiveParent: Bool = false) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)

        let backgroundColor: Color = {
            if isHovered {
                return Color.accentColor
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
                    .font(.system(size: 13 * scale, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foregroundColor)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .background(backgroundColor)
                    .transition(.opacity)
            } else {
                iconView(for: action.displayIcon(using: presenter))
                    .foregroundColor(foregroundColor)
                    .padding(.horizontal, {
                        if case .text = action.displayIcon(using: presenter) { return 6.0 * scale }
                        return 0.0
                    }())
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .background(backgroundColor)
                    .overlay(alignment: subBarAbove ? .top : .bottom) {
                        if isGroup {
                            GroupIndicatorTriangle(pointingUp: subBarAbove)
                                .fill(foregroundColor.opacity(0.65))
                                .frame(width: 4.0 * scale, height: 2.5 * scale)
                                .padding(subBarAbove ? .top : .bottom, 1.8 * scale)
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
                    if isHovering {
                        let frame = hoverFrames[.action(index)] ?? .zero
                        onRequestSubBarDwell?(action, index, frame)
                    } else {
                        onCancelSubBarDwell?()
                    }
                }
            case .perform:
                if action.chrome.launchesAI {
                    // AI Tools launcher opens scoped search palette on click; sub-bar opens on hover dwell
                    Button {
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
                        if isHovering {
                            let frame = hoverFrames[.action(index)] ?? .zero
                            onRequestSubBarDwell?(action, index, frame)
                        } else {
                            onCancelSubBarDwell?()
                        }
                    }
                } else {
                    // Existing perform button unchanged
                    Button {
                        onCancelSubBarDwell?()
                        if action.chrome.showsLoading {
                            onRunLoadingAction?(action)
                            return
                        }
                        onWillPerformAction?(action)
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
                                            isSecondaryClick: onClickIntent() == .secondary,
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
                                    isSecondaryClick: onClickIntent() == .secondary,
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
        .animation(.spring(response: PopupMetrics.inlineSpringResponse, dampingFraction: PopupMetrics.inlineSpringDamping), value: modeStore.inlineResults[action.id])
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
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundColor(isHovered ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                .frame(width: chevronWidth, height: barButtonHeight)
                .background(isHovered ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popupHoverTarget(target)
        .onHover { isHovering in
            useLocalHoverFallback(for: target, isHovering: isHovering)
        }
    }

    // MARK: - Opaque Background Helpers

    @ViewBuilder
    private var opaqueBackground: some View {
        switch effectiveTheme {
        case "dark":
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.20, green: 0.20, blue: 0.22))
        default:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.91, green: 0.91, blue: 0.93))
        }
    }

    private var opaqueBorder: Color {
        effectiveTheme == "light" ? Color.black.opacity(0.20) : Color.white.opacity(0.22)
    }

    private func updateHoveredTarget(for location: CGPoint?) {
        guard !isStatic else { return }
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        let oldTarget = hoveredTarget
        hoveredTarget = target
        reportHoveredAction()

        if case .action(let index) = target, index < pagedActions.count {
            let action = pagedActions[index]
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
            guard case .action(let index) = hoveredTarget, index < pagedActions.count else { return nil }
            return pagedActions[index]
        }()
        onHoveredActionChanged?(action)
    }

    private func useLocalHoverFallback(for target: PopupHoverTarget, isHovering: Bool) {
        guard !isStatic, !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            guard hoveredTarget != target else { return }
            hoveredTarget = target
            reportHoveredAction()
        } else if hoveredTarget == target {
            hoveredTarget = nil
            reportHoveredAction()
        }
    }

    // MARK: - Tooltip Management

    private func tooltipText(for target: PopupHoverTarget) -> String? {
        switch target {
        case .action(let index):
            guard index < pagedActions.count else { return nil }
            return pagedActions[index].displayTitle(using: presenter)
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
        ActionIconView(icon: icon, size: 13.5, scale: scale)
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
