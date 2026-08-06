// PopupSearchView.swift
// OpenClip
//
// The action-search palette: a focused text field filtering the full action catalog (enabled and
// disabled) as you type, rendered as one surface with the popup bar. Results appear above or
// below the field depending on popup position; up to 3 rows visible, scrollable beyond that.
import SwiftUI
import AppKit
import Core

@MainActor
public struct PopupSearchView: View {
    public let catalog: [any Action]
    public let context: ActionContext
    public let resultsAbove: Bool
    public let onResult: @MainActor (ActionResult) -> Void
    public let onExit: @MainActor () -> Void
    /// Routes AI preset selections (chrome source `.ai`) to the popup's AI card flow instead of
    /// `perform`. Passed the registered AI action id (`ai.preset.<presetID>`); nil disables the
    /// route and falls back to `perform`.
    public let onRunAI: @MainActor (String) -> Void
    /// When non-nil, the palette is scoped to a parent action's sub-actions: it lists only those
    /// children and rerenders the field with the parent's icon + a "Search within ..." placeholder.
    public let scope: SearchScope?
    /// Called when the user drops the current scope (Esc with an empty query) back to the full list.
    public let onExitScope: @MainActor () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    @AppStorage("popupTheme") private var selectedTheme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    /// Hover follows the same mechanism as the bar: the AX global-mouse location hit-tested
    /// against registered frames (instant), with an `.onHover` fallback when global monitoring
    /// is unavailable. This avoids SwiftUI's delayed hover for the palette's small targets.
    @ObservedObject private var hoverState = PopupHoverState.shared
    @State private var hoverFrames: [SearchHoverTarget: CGRect] = [:]
    @State private var hoveredTarget: SearchHoverTarget?

    private var effectiveTheme: String {
        let category = PopupThemeModel.category(fromStored: selectedTheme)
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    /// When scoped, only the parent's resolved children are candidates for matching/search.
    private var scopedChildren: [any Action]? {
        scope.map { $0.children }
    }

    private var searchIndex: [ActionSearchIndex] {
        (scopedChildren ?? catalog).map { action in
            ActionSearchIndex(
                id: action.id,
                title: action.displayTitle,
                keywords: searchKeywords(for: action),
                action: action
            )
        }
    }

    private var results: [ActionSearchIndex] {
        ActionSearch.search(query, in: searchIndex)
    }

    private var visibleResultCount: Int {
        min(results.count, Constants.searchMaxRows)
    }

    /// Scroll-viewport height: full rows up to `searchMaxRows`, plus a partial extra row when
    /// more results exist so the next action peeks and signals scrollability.
    private var resultsViewportHeight: CGFloat {
        let base = CGFloat(visibleResultCount) * Constants.searchResultRowHeight
        guard results.count > visibleResultCount else { return base }
        return base + Constants.searchPeekRowFraction * Constants.searchResultRowHeight
    }

    public init(
        catalog: [any Action],
        context: ActionContext,
        resultsAbove: Bool,
        scope: SearchScope? = nil,
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onExit: @escaping @MainActor () -> Void,
        onExitScope: @escaping @MainActor () -> Void = {},
        onRunAI: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.context = context
        self.resultsAbove = resultsAbove
        self.scope = scope
        self.onResult = onResult
        self.onExit = onExit
        self.onExitScope = onExitScope
        self.onRunAI = onRunAI
    }

    public var body: some View {
        VStack(spacing: 0) {
            if resultsAbove {
                resultsList
                searchFieldRow
            } else {
                searchFieldRow
                resultsList
            }
        }
        .frame(width: 280)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onPreferenceChange(SearchHoverFramePreferenceKey.self) { frames in
            hoverFrames = frames
            updateHoveredTarget(for: hoverState.location)
        }
        .onReceive(hoverState.$location) { location in
            updateHoveredTarget(for: location)
        }
        .onAppear {
            isFocused = true
        }
    }

    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            searchIcon
            TextField(scope == nil ? "Search all actions" : "Search within \(scope?.parent.displayTitle ?? "")", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .focused($isFocused)
                .onSubmit { runSelected() }
                .onKeyPress { press in
                    // Attached to the focused field: Escape drops the scope (or exits search),
                    // up/down move the result selection.
                    if press.key == .escape {
                        exitSearch()
                        return .handled
                    }
                    if press.key == .upArrow {
                        moveSelection(by: -1)
                        return .handled
                    }
                    if press.key == .downArrow {
                        moveSelection(by: 1)
                        return .handled
                    }
                    return .ignored
                }
            let isEscHovered = hoveredTarget == .esc
            Button(action: exitSearch) {
                Text("esc")
                    .font(.caption2)
                    .foregroundColor(isEscHovered ? .white : PopupThemeModel.restSecondary(for: effectiveTheme))
                    .frame(minWidth: 24)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        isEscHovered ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isEscHovered ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.45), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Exit search")
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .searchHoverTarget(.esc)
            .onHover { hovering in
                useLocalHoverFallback(for: .esc, isHovering: hovering)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    /// Closes the palette by dropping the scope back to the full list (Esc with an empty scoped
    /// query) or, when already flat, exiting search entirely.
    private func exitSearch() {
        if scope != nil { onExitScope() } else { onExit() }
    }

    /// Leading field icon: the scope parent's icon when scoped, otherwise the palette's ⌘ glyph.
    private var searchIcon: some View {
        if let parent = scope?.parent {
            return AnyView(actionIcon(parent).foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme)))
        } else {
            return AnyView(
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
            )
        }
    }

    /// Render an action's icon (symbol / iconify / url / local / text) at field size.
    @ViewBuilder private func actionIcon(_ action: any Action) -> some View {
        switch action.icon {
        case .symbol(let name):
            if name.contains(":") {
                AnyIconView(iconId: name)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: name).font(.system(size: 14))
            }
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "circle.dashed")
                }
            }
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        case .text(let text):
            Text(text).font(.system(size: 13, weight: .medium))
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        resultRow(item: item, index: index)
                            .id(item.id)
                    }
                }
            }
            .frame(height: resultsViewportHeight)
            .onChange(of: selectedIndex) { _, newValue in
                guard newValue < results.count else { return }
                proxy.scrollTo(results[newValue].id)
            }
        }
    }

    @ViewBuilder
    private func resultRow(item: ActionSearchIndex, index: Int) -> some View {
        let isSelected = index == selectedIndex || hoveredTarget == .row(index)
        Button {
            selectedIndex = index
            runSelected()
        } label: {
            HStack(spacing: 8) {
                iconView(for: rowIcon(for: item.action))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                    .foregroundColor(isSelected ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isSelected ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                Spacer(minLength: 8)
                if let badge = badgeText(for: item.action) {
                    Text(badge)
                        .font(.caption2)
                        .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Constants.searchResultRowHeight)
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .searchHoverTarget(.row(index))
        .onHover { hovering in
            useLocalHoverFallback(for: .row(index), isHovering: hovering)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    private func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let action = results[selectedIndex].action
        // AI preset actions render their result in the popup's AI card (same flow as the Sparkles
        // toolbar), so route them there instead of through `perform`.
        if case .ai = action.chrome.source {
            onRunAI(action.id)
            return
        }
        Task { @MainActor in
            do {
                // Same match plumbing as the bar's perform path: thread the visibility match into
                // the perform context so placeholders/env see the same match that enabled the row.
                let match = action.matchInfo(for: context)
                let performContext = match.map {
                    ActionContext(selection: context.selection, modifiers: context.modifiers, match: $0)
                } ?? context
                let result = try await action.perform(performContext)
                onResult(result)
            } catch {
                onResult(.showStatus(StatusFeedback(error: error)))
            }
        }
    }

    private func searchKeywords(for action: any Action) -> String {
        var parts = [action.title]
        if case .extensionPkg(let packageID) = action.chrome.source {
            parts.append(packageID)
        }
        if case .extensionPkg(let packageID) = action.chrome.badge {
            parts.append(packageID)
        }
        return parts.joined(separator: " ")
    }

    /// Rows are strictly [icon | text]: a text icon in the icon column would duplicate the title, so
    /// resolve symbol-first (custom override, then the action's SF Symbol preference), matching the
    /// preferences table.
    private func rowIcon(for action: any Action) -> ActionIcon {
        switch action.displayIcon {
        case .symbol, .url, .local:
            return action.displayIcon
        case .text:
            if let configurable = action as? any ConfigurableAction {
                return .symbol(configurable.preferenceIconName)
            }
            return action.displayIcon
        }
    }

    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        switch icon {
        case .symbol(let name):
            if name.contains(":") {
                // Iconify format "prefix:name" — render via SDWebImage + SVGCoder (matches the bar).
                AnyIconView(iconId: name)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: name)
            }
        case .text(let text):
            Text(text).font(.system(size: 11))
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "circle.dashed")
                }
            }
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }
    }

    private func badgeText(for action: any Action) -> String? {
        switch action.chrome.badge {
        case .script: return "script"
        case .url: return "url"
        case .custom: return "custom"
        case .extensionPkg(let id): return id
        case .none:
            if case .extensionPkg = action.chrome.source { return "extension" }
            return nil
        }
    }

    // MARK: - Hover (same location-based mechanism as the bar)

    /// The hovered target is derived from the shared mouse location, hit-tested against the
    /// frames each row/esc registers in the popup's named coordinate space.
    private func updateHoveredTarget(for location: CGPoint?) {
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
    }

    /// Local `.onHover` fallback used only when the AX global mouse monitor is unavailable;
    /// otherwise the location-driven path above owns hover (instant, no SwiftUI hover delay).
    private func useLocalHoverFallback(for target: SearchHoverTarget, isHovering: Bool) {
        guard !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            guard hoveredTarget != target else { return }
            hoveredTarget = target
        } else if hoveredTarget == target {
            hoveredTarget = nil
        }
    }
}

private enum SearchHoverTarget: Hashable {
    case row(Int)
    case esc
}

private struct SearchHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SearchHoverTarget: CGRect] = [:]

    static func reduce(value: inout [SearchHoverTarget: CGRect], nextValue: () -> [SearchHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func searchHoverTarget(_ target: SearchHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }
}
