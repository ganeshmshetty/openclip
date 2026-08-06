// PopupView.swift
// OpenClip
//
// Renders the main floating action bar popup view presenting available actions, transform menus,
// inline completion buttons, and (in search mode) the action-search palette.
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
    /// Called with (resultText, isError) when the AI result is ready to show in a separate overlay panel
    public let onAIResult: (@MainActor (String, Bool) -> Void)?
    /// Called when the AI overlay should be dismissed
    public let onAIDismiss: (@MainActor () -> Void)?
    /// Called when the hovered action changes (nil when nothing hovered). Drives the hover info bubble.
    public let onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)?
    /// Opens a scoped palette for a bar row's sub-actions (group rows via `.openSubActions` and the
    /// AI Tools launcher): the controller resolves + owns the SearchScope and enters search mode.
    public let onEnteredScopedSearch: (@MainActor (any Action) -> Void)?
    /// True when this is a static preview — hover tracking is disabled entirely so the
    /// preview never reacts to (or leaks into) the real popup's shared hover state.
    private let isStatic: Bool

    @AppStorage("popupTheme") private var selectedTheme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"
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
    
    @AppStorage("completionCopyToClipboard") private var completionCopyToClipboard: Bool = false
    
    @State private var currentPage = 0
    /// The hover state this bar observes. The real popup uses the shared instance; the
    /// static preview passes its own so the two never affect each other.
    @ObservedObject private var hoverState: PopupHoverState
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

    private let buttonWidth: CGFloat = 36
    private let chevronWidth: CGFloat = 26
    private let pageSize = 7


    public init(
        actions: [any Action],
        context: ActionContext,
        initialAICardAboveBar: Bool = false,
        hoverState: PopupHoverState = .shared,
        isStatic: Bool = false,
        modeStore: PopupModeStore = PopupModeStore(),
        onEnterSearch: @escaping @MainActor () -> Void = {},
        onExitSearch: @escaping @MainActor () -> Void = {},
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onContentSizeChange: (@MainActor (CGSize) -> Void)? = nil,
        onAIStateChange: (@MainActor (Bool, Bool) -> Void)? = nil,
        onAIResult: (@MainActor (String, Bool) -> Void)? = nil,
        onAIDismiss: (@MainActor () -> Void)? = nil,
        onHoveredActionChanged: (@MainActor ((any Action)?) -> Void)? = nil,
        onEnteredScopedSearch: (@MainActor (any Action) -> Void)? = nil
    ) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
        self.onContentSizeChange = onContentSizeChange
        self.onAIStateChange = onAIStateChange
        self.onAIResult = onAIResult
        self.onAIDismiss = onAIDismiss
        self.onHoveredActionChanged = onHoveredActionChanged
        self.onEnteredScopedSearch = onEnteredScopedSearch
        self.isStatic = isStatic
        self._hoverState = ObservedObject(wrappedValue: hoverState)
        self._modeStore = ObservedObject(wrappedValue: modeStore)
        self.onEnterSearch = onEnterSearch
        self.onExitSearch = onExitSearch
        self._aiCardAboveBar = State(initialValue: initialAICardAboveBar)
    }

    private var availableCompletions: [String] {
        guard let provider = actions.first(where: { $0 is any WordCompletionProviding }) as? any WordCompletionProviding,
              provider.isEnabled(for: context) else { return [] }
        return provider.fetchCompletions(for: context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasCompletions: Bool {
        return !availableCompletions.isEmpty
    }

    private var inCompletionMode: Bool {
        return hasCompletions && isShowingCompletions
    }

    /// Group row IDs (chrome stamps `.showSubActions`); sub-actions live under `\(groupID).\(subID)`.
    private var groupIDs: [String] {
        actions.compactMap { $0.chrome.popupBehavior == .showSubActions ? $0.id : nil }
    }

    /// Bar rows: everything except the inline completion pseudo-action and any group sub-action.
    /// Sub-action membership follows the ID-prefix convention (no parentGroupID marker).
    private var displayActions: [any Action] {
        actions.filter { action in
            guard action.id != "builtin.completion" else { return false }
            return !groupIDs.contains { action.id.hasPrefix($0 + ".") }
        }
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
        // Bar only — AI overlay lives in its own separate NSPanel managed by PopupWindowController
        mainBarStyled
    }


    @ViewBuilder
    private var mainBarStyled: some View {
        let baseView = Group {
            if effectiveTheme == "glass" {
                let glassBorderColor: Color = effectiveColorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
                
                if #available(macOS 26, *) {
                    unifiedHStack
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
                } else {
                    unifiedHStack
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
                }
            } else {
                unifiedHStack
                    .background(opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 6, x: 0, y: 3)
            }
        }

        baseView
            .environment(\.colorScheme, effectiveColorScheme)
            .overlay(processingGlowBorder)
    }

    @ViewBuilder
    private var processingGlowBorder: some View {
        if isProcessingAI {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            actionsHStack
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        PopupSearchView(
            catalog: ActionCoordinator.shared.searchCatalog,
            context: context,
            resultsAbove: modeStore.searchResultsAbove,
            scope: modeStore.scope,
            onResult: onResult,
            onExit: onExitSearch,
            onExitScope: {
                modeStore.scope = nil
                onExitSearch()
            },
            onRunAI: { actionID in
                guard let preset = aiManager.preset(forActionID: actionID) else { return }
                onExitSearch()
                runAIPreset(prompt: preset.prompt)
            }
        )
    }

    // MARK: - AI Helpers

    private func runAIPreset(prompt: String) {
        cancelAITask()
        onAIDismiss?()

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
                    onAIResult?(response, false)
                }
            } catch is CancellationError {
                // no-op
            } catch let error as AIError where error == .cancelled {
                // no-op
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                onAIResult?(message, true)
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
            let list = availableCompletions
            ForEach(Array(list.enumerated()), id: \.offset) { index, word in
                let isLast = index == list.count - 1
                let isHovered = hoveredTarget == .completion(index)
                completionButton(word: word, index: index, isHovered: isHovered, showDivider: !isLast)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

            // Action-search affordance: command glyph (never the web-search magnifier). Kept outside
            // the paged actions so it always sits at the far-right edge on every page.
            let isHovered = hoveredTarget == .search
            let affordanceForeground = PopupThemeModel.restForeground(for: effectiveTheme)
            Button {
                onEnterSearch()
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .white : affordanceForeground)
                    .frame(width: buttonWidth, height: 28)
                    .background(isHovered ? Color.accentColor : Color.clear)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(maxWidth: 140)
                .padding(.horizontal, 10)
                .frame(minWidth: buttonWidth, minHeight: 28)
                .background(isHovered ? Color.accentColor : Color.clear)
                .overlay(alignment: .trailing) {
                    if showDivider && !isHovered {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 0.6, height: 28)
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

        let labelView = iconView(for: action.displayIcon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isHovered ? .white : restForeground)
            .padding(.horizontal, {
                if case .text = action.displayIcon { return 7.0 }
                return 0.0
            }())
            .frame(minWidth: buttonWidth, minHeight: 28)
            .background(isHovered ? Color.accentColor : Color.clear)
            .overlay(alignment: .trailing) {
                if showDivider && !isHovered {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 0.6, height: 28)
                }
            }
            .contentShape(Rectangle())

        switch action.gesturePolicy.singleClick {
        case .openSubActions:
            // Group rows (extension groups + the builtin transform group) open a scoped palette of
            // their children instead of a hover bubble. The controller resolves the SearchScope.
            Button {
                onEnteredScopedSearch?(action)
            } label: {
                labelView
            }
            .buttonStyle(.plain)
            .help(action.displayTitle)
            .accessibilityLabel(action.displayTitle)
            .popupHoverTarget(.action(index))
            .onHover { isHovering in
                useLocalHoverFallback(for: .action(index), isHovering: isHovering)
            }
        case .showResultBubble, .perform:
            if action.chrome.launchesAI {
                // The AI Tools launcher opens the scoped AI-presets palette (chrome-driven, no id
                // switching); it renders as a normal bar row and paginates like any other action.
                Button {
                    onEnteredScopedSearch?(action)
                } label: {
                    labelView
                }
                .buttonStyle(.plain)
                .applyBubbleTooltip(for: action, fallback: action.title)
                .accessibilityLabel(action.displayTitle)
                .popupHoverTarget(.action(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                }
            } else {
                Button {
                    Task {
                        do {
                            // Match plumbing (approach A): re-run the shared visibility evaluator for
                            // this action and thread the match into the perform context so placeholders
                            // and env vars see the same match that enabled the row.
                            let match = action.matchInfo(for: context)
                            let performContext = match.map {
                                ActionContext(selection: context.selection, modifiers: context.modifiers, match: $0)
                            } ?? context
                            let result = try await action.perform(performContext)
                            onResult(result)
                        } catch {
                            print("Action failed: \(error)")
                            // Decision 9: a thrown perform error surfaces uniformly as an error status
                            // and the popup stays.
                            onResult(.showStatus(StatusFeedback(error: error)))
                        }
                    }
                } label: {
                    labelView
                }
                .buttonStyle(.plain)
                .applyBubbleTooltip(for: action, fallback: action.title)
                .accessibilityLabel(action.displayTitle)
                .popupHoverTarget(.action(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .action(index), isHovering: isHovering)
                }
            }
        }
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredTarget == .chevron
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                .frame(width: chevronWidth, height: 28)
                .background(isHovered ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popupHoverTarget(.chevron)
        .onHover { isHovering in
            useLocalHoverFallback(for: .chevron, isHovering: isHovering)
        }
    }

    // MARK: - Opaque Background Helpers

    @ViewBuilder
    private var opaqueBackground: some View {
        switch effectiveTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.20, green: 0.20, blue: 0.22))
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    /// Maps the current hoveredTarget to its action (if any) and reports it upward for the info bubble.
    private func reportHoveredAction() {
        let action: (any Action)? = {
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
            if let nsImage = NSImage(contentsOf: url) {
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

@MainActor
public final class PopupHoverState: ObservableObject {
    public static let shared = PopupHoverState()

    @Published public var location: CGPoint?
    @Published public var usesGlobalMouseMonitoring = false

    public init() {}
}

private enum PopupHoverTarget: Hashable {
    case action(Int)
    case completion(Int)
    case chevron
    case search
}

private struct PopupHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [PopupHoverTarget: CGRect] = [:]

    static func reduce(value: inout [PopupHoverTarget: CGRect], nextValue: () -> [PopupHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PopupContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func popupHoverTarget(_ target: PopupHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }

    /// Uses the OS `.help()` tooltip unless the action has hover preview, in which case the
    /// info bubble replaces it (avoids double tooltips on PreviewProviding actions).
    @MainActor
    func applyBubbleTooltip(for action: any Action, fallback: String) -> some View {
        let usesInfoBubble = action.gesturePolicy.hoverPreview
        if usesInfoBubble {
            return AnyView(self.help(""))
        }
        return AnyView(self.help(fallback))
    }
}
