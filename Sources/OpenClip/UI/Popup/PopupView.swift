// PopupView.swift
// OpenClip
//
// Renders the main floating action bar popup view presenting available actions, transform menus,
// inline completion buttons, the action-search palette, and the native AI result card (which
// replaces the bar with AIResultCardView in content mode).
import SwiftUI
import AppKit
import CoreGraphics
import Core
import SDWebImageSwiftUI

// MARK: - Popup View

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void
    public let onContentSizeChange: (@MainActor (CGSize) -> Void)?
    /// active=true when AI is running or showing result; cardAboveBar=true when the card should render above the bar
    public let onAIStateChange: (@MainActor (Bool, Bool) -> Void)?
    /// Called with (resultText, isError, title) when the AI result is ready to show in the AI result
    /// card; `title` is the producing preset's title (falls back to "AI Tools" in the card).
    public let onAIResult: (@MainActor (String, Bool, String) -> Void)?
    /// Called when the AI result card should collapse back to the bar (back chevron).
    public let onExitContent: @MainActor () -> Void
    /// The AI result card's Paste/Copy buttons — explicit user requests routed through the
    /// controller's keep-open card-effect door (bypasses the paste-vs-copy re-decision).
    public let onCardEffect: @MainActor (ActionResult) -> Void
    /// Called when the hovered action changes (nil when nothing hovered). Drives the hovered-row
    /// tracking used by the right-click path.
    public let onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)?
    /// Opens a scoped palette for a bar row's sub-actions (group rows via `.openSubActions` and the
    /// AI Tools launcher): the controller resolves + owns the SearchScope and enters search mode.
    public let onEnteredScopedSearch: (@MainActor (any Action) -> Void)?
    /// Called when an action is actually run (bar / palette / AI), so the controller can record usage.
    public let onActionPerformed: (@MainActor (String) -> Void)?
    /// Called right before an action performs (before `onResult` can fire), so the controller can
    /// snapshot the action's declared delivery for the paste-vs-copy decision.
    public let onWillPerformAction: (@MainActor (any Action) -> Void)?
    /// Called when a `showsLoading` bar action is clicked: the controller early-closes the popup
    /// and runs the action via the loading toast flow instead of the inline perform path.
    public let onRunLoadingAction: (@MainActor (any Action) -> Void)?
    /// Returns the click intent captured at mouse-down for the current click, so the left-click
    /// perform path can thread a force-copy click (⇧-click) into the action context.
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent
    /// True when this is a static preview — hover tracking is disabled entirely so the
    /// preview never reacts to (or leaks into) the real popup's shared hover state.
    private let isStatic: Bool

    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @AppStorage(SettingKey.popupScale.name) private var popupScale: Double = SettingKey.popupScale.defaultValue
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
    private let onEnterSearch: @MainActor () -> Void
    private let onExitSearch: @MainActor () -> Void
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

    private var scale: CGFloat { CGFloat(popupScale) }
    private var buttonWidth: CGFloat { 36 * scale }
    private var chevronWidth: CGFloat { 26 * scale }
    private var barButtonHeight: CGFloat { 26 * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }
    private let pageSize = 7


    @MainActor
    public init(
        actions: [any Action],
        context: ActionContext,
        initialAICardAboveBar: Bool = false,
        hoverState: PopupHoverState = .shared,
        presenter: any ActionPresenting = ActionCustomizationManager.shared,
        isStatic: Bool = false,
        modeStore: PopupModeStore = PopupModeStore(),
        onEnterSearch: @escaping @MainActor () -> Void = {},
        onExitSearch: @escaping @MainActor () -> Void = {},
        onExitContent: @escaping @MainActor () -> Void = {},
        onCardEffect: @escaping @MainActor (ActionResult) -> Void = { _ in },
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onContentSizeChange: (@MainActor (CGSize) -> Void)? = nil,
        onAIStateChange: (@MainActor (Bool, Bool) -> Void)? = nil,
        onAIResult: (@MainActor (String, Bool, String) -> Void)? = nil,
        onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)? = nil,
        onEnteredScopedSearch: (@MainActor (any Action) -> Void)? = nil,
        onActionPerformed: (@MainActor (String) -> Void)? = nil,
        onWillPerformAction: (@MainActor (any Action) -> Void)? = nil,
        onRunLoadingAction: (@MainActor (any Action) -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary }
    ) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
        self.onContentSizeChange = onContentSizeChange
        self.onAIStateChange = onAIStateChange
        self.onAIResult = onAIResult
        self.onExitContent = onExitContent
        self.onCardEffect = onCardEffect
        self.onHoveredActionChanged = onHoveredActionChanged
        self.onEnteredScopedSearch = onEnteredScopedSearch
        self.onActionPerformed = onActionPerformed
        self.onWillPerformAction = onWillPerformAction
        self.onRunLoadingAction = onRunLoadingAction
        self.onClickIntent = onClickIntent
        self.isStatic = isStatic
        self.hoverState = hoverState
        self.presenter = presenter
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

    private var totalPages: Int {
        guard !displayActions.isEmpty else { return 1 }
        return Int(ceil(Double(displayActions.count) / Double(pageSize)))
    }

    private var pagedActions: [any Action] {
        let list = displayActions
        let startIndex = currentPage * pageSize
        guard startIndex < list.count else { return [] }
        let endIndex = min(startIndex + pageSize, list.count)
        return Array(list[startIndex..<endIndex])
    }

    private var hasLeftChevron: Bool { currentPage > 0 }
    private var hasRightChevron: Bool { currentPage < totalPages - 1 }

    public var body: some View {
        barContent
            .padding(16)
            .coordinateSpace(name: "popupHoverSpace")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PopupContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
                hoverFrames = frames
                updateHoveredTarget(for: hoverState.location)
            }
            .onPreferenceChange(PopupContentSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                onContentSizeChange?(size)
            }
            .onReceive(hoverState.$location) { location in
                updateHoveredTarget(for: location)
            }
            .onChange(of: isProcessingAI) { _, active in
                onAIStateChange?(active, aiCardAboveBar)
            }
            .onDisappear {
                cancelAITask()
            }
    }

    // MARK: - Unified Bar Container

    @ViewBuilder
    private var barContent: some View {
        if modeStore.mode == .content {
            aiResultCard
        } else {
            mainBarStyled
        }
    }

    /// The AI result card: renders the native AIResultCardView inline on the popup panel in place
    /// of the bar (content mode). Paste/Copy are explicit user requests routed through
    /// onCardEffect (bypassing the paste-vs-copy re-decision) that both dismiss the popup; the
    /// Paste button is hidden when the target app can't paste; the back chevron collapses back to
    /// the bar.
    @ViewBuilder
    private var aiResultCard: some View {
        if let payload = modeStore.aiResult {
            AIResultCardView(
                payload: payload,
                canPaste: modeStore.canPaste,
                onExit: { onExitContent() },
                onPaste: { onCardEffect(.paste(payload.text)) },
                onCopy: { onCardEffect(.copy(payload.text)) }
            )
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
        }
    }


    @ViewBuilder
    private var mainBarStyled: some View {
        let baseView = Group {
            if effectiveTheme == "glass" {
                let glassBorderColor: Color = effectiveColorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
                
                if #available(macOS 26, *) {
                    barStack
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
                } else {
                    barStack
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
                }
            } else {
                barStack
                    .background(opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 6, x: 0, y: 3)
            }
        }

        baseView
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
        if modeStore.mode == .search {
            searchContent
        } else if inCompletionMode {
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

    @ViewBuilder
    private var searchContent: some View {
        PopupSearchView(
            catalog: searchCatalog,
            context: context,
            resultsAbove: modeStore.searchResultsAbove,
            scope: modeStore.scope,
            usageRecency: ActionUsageStore.shared.recency,
            onResult: onResult,
            onExit: onExitSearch,
            onExitScope: {
                modeStore.scope = nil
                onExitSearch()
            },
            onRunAI: { actionID in
                onActionPerformed?(actionID)
                guard let preset = aiManager.preset(forActionID: actionID) else { return }
                onExitSearch()
                runAIPreset(prompt: preset.prompt, title: preset.title)
            },
            onActionPerformed: onActionPerformed,
            onWillPerformAction: onWillPerformAction,
            onRunLoadingAction: onRunLoadingAction,
            onClickIntent: onClickIntent
        )
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
        aiTask = Task { @MainActor in
            isProcessingAI = true
            defer {
                if !Task.isCancelled {
                    isProcessingAI = false
                }
            }

            do {
                let provider = aiManager.currentProvider
                let response = try await provider.process(prompt: prompt, text: selectionText)
                guard !Task.isCancelled else { return }

                if provider.type == .browser || response.isEmpty {
                    if response.isEmpty { onResult(.success) }
                } else {
                    onAIResult?(response, false, title)
                }
            } catch is CancellationError {
                // no-op
            } catch let error as AIError where error == .cancelled {
                // no-op
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                onAIResult?(message, true, title)
            }
        }
    }

    private func cancelAITask() {
        aiTask?.cancel()
        aiTask = nil
        isProcessingAI = false
    }

    // MARK: - Completion Mode Bar Layout

    private var completionHStack: some View {
        HStack(spacing: 0) {
            // Far Left: Up Arrow button toggles to normal actions mode
            chevronButton(systemImage: "chevron.up", label: "Back to actions") {
                isShowingCompletions = false
            }
            
            // Horizontal Completion Word Items
            let list = cachedCompletions
            ForEach(Array(list.enumerated()), id: \.offset) { index, word in
                let isLast = index == list.count - 1
                let isHovered = hoveredTarget == .completion(index)
                completionButton(word: word, index: index, isHovered: isHovered, showDivider: !isLast)
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
                    isShowingCompletions = true
                }
            }

            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let showDivider = true
                let isHovered = hoveredTarget == .action(index)
                actionButton(action: action, index: index, isHovered: isHovered, showDivider: showDivider)
            }

            // Sparkles AI launcher is a normal action row (chrome.launchesAI); it paginates with
            // the other actions and its click opens AI mode via the branch in actionButton.

            if hasLeftChevron {
                chevronButton(systemImage: "chevron.left", label: "Previous page") { currentPage -= 1 }
            }
            if hasRightChevron {
                chevronButton(systemImage: "chevron.right", label: "Next page") { currentPage += 1 }
            }

            // Action-search affordance: magnifyingglass glyph. Kept outside
            // the paged actions so it always sits at the far-right edge on every page.
            let isHovered = hoveredTarget == .search
            let affordanceForeground = PopupThemeModel.restForeground(for: effectiveTheme)
            let dividerColor = PopupThemeModel.dividerColor(for: effectiveTheme)
            Button {
                onEnterSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundColor(isHovered ? .white : affordanceForeground)
                    .frame(width: buttonWidth, height: barButtonHeight)
                    .background(isHovered ? Color.accentColor : Color.clear)
                    // Pagination chevrons sit between the last action and this glyph; without a
                    // divider the command icon would appear glued to the chevrons.
                    .overlay(alignment: .leading) {
                        if (hasLeftChevron || hasRightChevron) && !isHovered {
                            Rectangle()
                                .fill(dividerColor)
                                .frame(width: 0.6, height: barButtonHeight)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search all actions")
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
    private func completionButton(word: String, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        let dividerColor = PopupThemeModel.dividerColor(for: effectiveTheme)

        Button {
            onResult(.paste(word))
        } label: {
            Text(word)
                .font(.system(size: 13 * scale, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(maxWidth: 140 * scale)
                .padding(.horizontal, 10 * scale)
                .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                .background(isHovered ? Color.accentColor : Color.clear)
                .overlay(alignment: .trailing) {
                    if showDivider && !isHovered {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 0.6, height: barButtonHeight)
                    }
                }
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
    private func actionButton(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        let dividerColor = PopupThemeModel.dividerColor(for: effectiveTheme)

        let labelView = iconView(for: action.displayIcon(using: presenter))
            .font(.system(size: 13 * scale, weight: .medium))
            .foregroundColor(isHovered ? .white : restForeground)
            .padding(.horizontal, {
                if case .text = action.displayIcon(using: presenter) { return 7.0 * scale }
                return 0.0
            }())
            .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
            .background(isHovered ? Color.accentColor : Color.clear)
            .overlay(alignment: .trailing) {
                if showDivider && !isHovered {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 0.6, height: barButtonHeight)
                }
            }
            .contentShape(Rectangle())

        switch action.gesturePolicy.singleClick {
        case .openSubActions:
            // Group rows (extension groups) open a scoped palette of
            // their children instead of performing directly. The controller resolves the SearchScope.
            Button {
                onEnteredScopedSearch?(action)
            } label: {
                labelView
            }
            .buttonStyle(.plain)
            .help(action.displayTitle(using: presenter))
            .accessibilityLabel(action.displayTitle(using: presenter))
            .popupHoverTarget(.action(index))
            .onHover { isHovering in
                useLocalHoverFallback(for: .action(index), isHovering: isHovering)
            }
        case .perform:
            if action.chrome.launchesAI {
                // The AI Tools launcher opens the scoped AI-presets palette (chrome-driven, no id
                // switching); it renders as a normal bar row and paginates like any other action.
                Button {
                    onEnteredScopedSearch?(action)
                } label: {
                    labelView
                }
                .buttonStyle(.plain)
                .applyContentTooltip(for: action, fallback: action.title)
                .accessibilityLabel(action.displayTitle(using: presenter))
                .popupHoverTarget(.action(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                }
            } else {
                Button {
                    if action.chrome.showsLoading {
                        onRunLoadingAction?(action)
                        return
                    }
                    Task {
                        do {
                            onWillPerformAction?(action)
                            onActionPerformed?(action.id)
                            // Match plumbing (approach A): re-run the shared visibility evaluator for
                            // this action and thread the match into the perform context so placeholders
                            // and env vars see the same match that enabled the row.
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
                            // Decision 9: a thrown perform error surfaces uniformly as an error status
                            // and the popup stays.
                            onResult(.showStatus(StatusFeedback(error: error)))
                        }
                    }
                } label: {
                    labelView
                }
                .buttonStyle(.plain)
                .applyContentTooltip(for: action, fallback: action.title)
                .accessibilityLabel(action.displayTitle(using: presenter))
                .popupHoverTarget(.action(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                }
            }
        }
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        // Each chevron gets its own hover target keyed by its glyph, so hovering the
        // pagination right/left chevrons never highlights the completion-mode up chevron
        // (or the completion toggle) and vice-versa.
        let target: PopupHoverTarget = .chevron(systemImage)
        let isHovered = hoveredTarget == target
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11 * scale, weight: .semibold))
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
        hoveredTarget = target
        reportHoveredAction()
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

    // MARK: - Icon Helper

    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        switch icon {
        case .symbol(let name):
            if name.contains(":") {
                // Iconify format "prefix:name" — render via SDWebImage + SVGCoder
                AnyIconView(iconId: name)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: name)
            }
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
                } else {
                    Image(systemName: phase.error != nil ? "exclamationmark.triangle" : "circle.dashed")
                }
            }
        case .local(let url):
            if let nsImage = LocalIconCache.shared.image(for: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
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
