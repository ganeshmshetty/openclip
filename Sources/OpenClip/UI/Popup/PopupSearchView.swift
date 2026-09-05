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
    /// Recency counters (action ID → MRU counter) captured at palette entry; breaks ties below
    /// match quality. Constant for the palette session. See `ActionUsageStore`.
    public let usageRecency: [String: Int]
    /// Called when an action is actually run, so the controller can record usage.
    public let onActionPerformed: (@MainActor (String) -> Void)?
    /// Called right before an action performs (before `onResult` can fire), so the controller can
    /// snapshot the action's declared delivery for the paste-vs-copy decision.
    public let onWillPerformAction: (@MainActor (any Action) -> Void)?
    /// Called when a `showsLoading` palette result is selected: the controller early-closes the
    /// popup and runs the action via the loading toast flow instead of the inline perform path.
    public let onRunLoadingAction: (@MainActor (any Action) -> Void)?
    /// Returns the click intent captured at mouse-down for the current click, so the palette's
    /// perform path can thread a force-copy click (⇧-click) into the action context.
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool
    /// Set by keyboard selection moves so `.onChange` auto-scrolls the list; hover-driven
    /// selection changes leave it false so hovering the edge of a row never shifts the list.
    @State private var scrollSelectionOnKeyboard = false

    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @Environment(\.colorScheme) private var colorScheme

    /// Hover follows the same mechanism as the bar: the AX global-mouse location hit-tested
    /// against registered frames (instant), with an `.onHover` fallback when global monitoring
    /// is unavailable. This avoids SwiftUI's delayed hover for the palette's small targets.
    /// Deliberately *not* `@ObservedObject`: `location` publishes at event-monitor rate, and
    /// observing the whole object re-evaluates the entire palette body per mouse move. Only
    /// `hoverState.$location` is subscribed to via `.onReceive`.
    private let hoverState = PopupHoverState.shared
    /// Resolves user-customized action titles/icons (composition-injected, defaults to the shared
    /// customization manager — never a hidden singleton reference inside the Action extension).
    private let presenter: any ActionPresenting
    @State private var hoverFrames: [SearchHoverTarget: CGRect] = [:]
    @State private var hoveredTarget: SearchHoverTarget?

    private var effectiveTheme: String {
        let category = PopupThemeModel.category(fromStored: selectedTheme)
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    /// The precomputed search index for this palette session: scoped children when scoped, the
    /// full catalog otherwise. Built once in `init` (and on scope changes via `rebuildSearchIndex`)
    /// instead of on every body evaluation — indexing walks the whole catalog resolving titles +
    /// keywords, so it must not re-run for every keystroke/hover.
    @State private var searchIndex: [ActionSearchIndex] = []

    /// The ranked results for the current `query`. Stored, not computed: body evaluation reads
    /// `results` several times per pass (count, viewport height, the row ForEach) and re-evaluates
    /// on hover/selection moves too — a computed property would re-run the full filter+sort on
    /// every one of those reads. Recomputed exactly once per query change (and per scope rebuild).
    @State private var results: [ActionSearchIndex] = []

    /// Scroll-viewport height: constant height based on searchMaxRows + peek fraction so the
    /// search palette maintains a stable size and does not collapse or jump as the user types.
    private var resultsViewportHeight: CGFloat {
        (CGFloat(PopupMetrics.searchMaxRows) + PopupMetrics.searchPeekRowFraction) * PopupMetrics.searchResultRowHeight
    }

    public init(
        catalog: [any Action],
        context: ActionContext,
        resultsAbove: Bool,
        presenter: any ActionPresenting = ActionCustomizationManager.shared,
        scope: SearchScope? = nil,
        usageRecency: [String: Int] = [:],
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onExit: @escaping @MainActor () -> Void,
        onExitScope: @escaping @MainActor () -> Void = {},
        onRunAI: @escaping @MainActor (String) -> Void = { _ in },
        onActionPerformed: (@MainActor (String) -> Void)? = nil,
        onWillPerformAction: (@MainActor (any Action) -> Void)? = nil,
        onRunLoadingAction: (@MainActor (any Action) -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary }
    ) {
        self.catalog = catalog
        self.context = context
        self.resultsAbove = resultsAbove
        self.presenter = presenter
        self.scope = scope
        self.usageRecency = usageRecency
        self.onResult = onResult
        self.onExit = onExit
        self.onExitScope = onExitScope
        self.onRunAI = onRunAI
        self.onActionPerformed = onActionPerformed
        self.onWillPerformAction = onWillPerformAction
        self.onRunLoadingAction = onRunLoadingAction
        self.onClickIntent = onClickIntent
        // Index once at entry: the palette is recreated on every search entry (mode + scope
        // transition together), so the current catalog/scope are captured here. The initial query
        // is empty, so the ranked results are just the full index in order.
        let initialIndex = Self.buildIndex(catalog: catalog, scope: scope, usageRecency: usageRecency, presenter: presenter)
        _searchIndex = State(initialValue: initialIndex)
        _results = State(initialValue: initialIndex)
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
        .frame(width: PopupMetrics.searchPanelContentWidth)
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.searchCornerRadius, style: .continuous))
        .onPreferenceChange(SearchHoverFramePreferenceKey.self) { frames in
            MainActor.assumeIsolated {
                hoverFrames = frames
                updateHoveredTarget(for: hoverState.location)
            }
        }
        .onReceive(hoverState.$location) { location in
            updateHoveredTarget(for: location)
        }
        .onChange(of: query) { _, newValue in
            results = ActionSearch.search(newValue, in: searchIndex)
            selectedIndex = 0
        }
        .onChange(of: scope?.parent.id) { _, _ in
            rebuildSearchIndex()
        }
        .onAppear {
            isFocused = true
        }
    }

    private var searchFieldRow: some View {
        HStack(spacing: 8) {
            searchIcon
            TextField(
                scope == nil
                    ? String(localized: "Search all actions")
                    : String(localized: "Search within \(scope?.parent.displayTitle(using: presenter) ?? "")"),
                text: $query
            )
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
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
            )
        }
    }

    /// Render an action's icon (symbol / iconify / url / local / text) at field size.
    private func actionIcon(_ action: any Action) -> some View {
        ActionIconView(icon: rowIcon(for: action), size: 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if results.isEmpty {
                    VStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text(query.isEmpty ? String(localized: "No matching actions") : String(localized: "No matches for “\(query)”"))
                                .font(.system(size: 13))
                                .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                            Text("Press esc to go back")
                                .font(.system(size: 11))
                                .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme).opacity(0.7))
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity, minHeight: resultsViewportHeight)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            resultRow(item: item, index: index)
                                .id(item.id)
                        }
                    }
                }
            }
            .frame(height: resultsViewportHeight)
            .onChange(of: selectedIndex) { _, newValue in
                guard scrollSelectionOnKeyboard else { return }
                scrollSelectionOnKeyboard = false
                guard newValue < results.count else { return }
                proxy.scrollTo(results[newValue].id)
            }
        }
    }

    @ViewBuilder
    private func resultRow(item: ActionSearchIndex, index: Int) -> some View {
        // Hover moves the selection (Spotlight-style), so exactly one row is highlighted:
        // `selectedIndex` is updated by the hover path before this is recomputed.
        let isSelected = index == selectedIndex
        Button {
            selectedIndex = index
            runSelected()
        } label: {
            HStack(spacing: 8) {
                iconView(for: rowIcon(for: item.action))
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                    .foregroundColor(isSelected ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                Text(item.title)
                    .font(.system(size: 13, weight: .regular))
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
            .frame(height: PopupMetrics.searchResultRowHeight)
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
        let newIndex = min(max(selectedIndex + delta, 0), results.count - 1)
        guard newIndex != selectedIndex else { return }
        scrollSelectionOnKeyboard = true
        selectedIndex = newIndex
    }

    private func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let action = results[selectedIndex].action
        // AI preset actions render their result in the popup's AI card (same flow as the Sparkles
        // toolbar), so route them there instead of through `perform`.
        if ActionIdentity.isAIPreset(action) {
            onRunAI(action.id)
            return
        }
        if action.chrome.showsLoading {
            if let onRunLoadingAction {
                onRunLoadingAction(action)
                return
            }
            // No loading callback wired up (e.g. a preview): fall through to the inline perform path.
        }
        onWillPerformAction?(action)
        onActionPerformed?(action.id)
        Task { @MainActor in
            do {
                // Same match plumbing as the bar's perform path: thread the visibility match into
                // the perform context so placeholders/env see the same match that enabled the row.
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
                onResult(.toast(StatusFeedback(error: error)))
            }
        }
    }

    /// Indexes the palette's candidates (scoped children when scoped, the full catalog otherwise)
    /// once per palette entry. Runs only when the catalog/scope inputs change, never per body eval.
    static func buildIndex(catalog: [any Action], scope: SearchScope?, usageRecency: [String: Int], presenter: any ActionPresenting) -> [ActionSearchIndex] {
        let candidates = scope?.children ?? catalog
        // The unscoped palette lists leaf actions only: container rows (group rows) are hidden so
        // the results never surface an inert row that performs `.none`. Their sub-actions are
        // indexed directly, and each group's title/name is folded into its children's keywords
        // (see `searchKeywords`) so typing the group name still surfaces its sub-actions. Scoped
        // palettes receive pre-resolved children (no container rows), so they pass through.
        let containerIDs = scope == nil
            ? Set(catalog.filter { $0.chrome.popupBehavior == .showSubActions }.map(\.id))
            : []
        return candidates
            .filter { !containerIDs.contains($0.id) }
            .map { action in
                ActionSearchIndex(
                    id: action.id,
                    title: action.displayTitle(using: presenter),
                    keywords: Self.searchKeywords(for: action, in: catalog),
                    action: action,
                    usageRecency: usageRecency[action.id] ?? 0
                )
            }
    }

    /// Rebuilds the index when the scope changes in place. The view is normally recreated per
    /// palette entry (init), so this is a defensive guard for scope transitions that keep
    /// `.search` mounted. The catalog is captured at entry; the palette is ephemeral.
    private func rebuildSearchIndex() {
        let index = Self.buildIndex(catalog: catalog, scope: scope, usageRecency: usageRecency, presenter: presenter)
        searchIndex = index
        results = ActionSearch.search(query, in: index)
        selectedIndex = 0
    }

    private static func searchKeywords(for action: any Action, in catalog: [any Action]) -> String {
        var parts = [action.title]
        if let packageID = ActionIdentity.extensionPackageID(of: action) {
            parts.append(packageID)
        }
        if case .extensionPkg(let packageID) = action.chrome.badge {
            parts.append(packageID)
        }
        // Action-declared keywords (e.g. from manifest or custom metadata)
        parts.append(contentsOf: action.keywords)
        // Multi-lingual search synonyms dictionary (EN, ZH-Hans, ZH-Hant, FR, JA)
        parts.append(contentsOf: ActionSearchKeywords.keywords(for: action.id, actionTitle: action.title))
        // Fold each container (group) row's title + package name + keywords into its sub-actions' keywords.
        // The group row is filtered out of the palette, so its name must index its children to
        // stay searchable.
        for group in catalog where group.chrome.popupBehavior == .showSubActions {
            guard group.id != action.id else { continue }
            let isMember: Bool
            if let provider = group as? any SubActionProviding {
                isMember = provider.subActions(in: catalog).contains { $0.id == action.id }
            } else {
                isMember = action.id.hasPrefix(group.id + ".")
            }
            guard isMember else { continue }
            parts.append(group.title)
            parts.append(contentsOf: group.keywords)
            parts.append(contentsOf: ActionSearchKeywords.keywords(for: group.id, actionTitle: group.title))
            if case .extensionPkg(let packageName) = group.chrome.badge {
                parts.append(packageName)
            }
        }
        return parts.joined(separator: " ")
    }

    /// Rows are strictly [icon | text]: a text icon in the icon column would duplicate the title, so
    /// resolve symbol-first (custom override, then the action's SF Symbol preference), matching the
    /// preferences table.
    private func rowIcon(for action: any Action) -> ActionIcon {
        if ActionIdentity.isAIPreset(action) {
            return .symbol(Constants.defaultAIIconSymbol)
        }
        let resolved = action.displayIcon(using: presenter)
        switch resolved {
        case .symbol, .url, .local:
            return resolved
        case .text:
            if let configurable = action as? any ConfigurableAction {
                return .symbol(configurable.preferenceIconName)
            }
            return resolved
        }
    }

    private func iconView(for icon: ActionIcon) -> some View {
        ActionIconView(icon: icon, size: 14)
    }

    private func badgeText(for action: any Action) -> String? {
        switch action.chrome.badge {
        case .script: return "script"
        case .url: return "url"
        case .custom: return "custom"
        case .extensionPkg: return nil
        case .none:
            if ActionIdentity.isExtension(action) { return "extension" }
            return nil
        }
    }

    // MARK: - Hover (same location-based mechanism as the bar)

    /// The hovered target is derived from the shared mouse location, hit-tested against the
    /// frames each row/esc registers in the popup's named coordinate space. Hovering a row
    /// moves the keyboard selection to it so the highlight follows the mouse.
    private func updateHoveredTarget(for location: CGPoint?) {
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
        if case .row(let index) = target, index < results.count {
            selectedIndex = index
        }
    }

    /// Local `.onHover` fallback used only when the AX global mouse monitor is unavailable;
    /// otherwise the location-driven path above owns hover (instant, no SwiftUI hover delay).
    private func useLocalHoverFallback(for target: SearchHoverTarget, isHovering: Bool) {
        guard !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            guard hoveredTarget != target else { return }
            hoveredTarget = target
            if case .row(let index) = target, index < results.count {
                selectedIndex = index
            }
        } else if hoveredTarget == target {
            hoveredTarget = nil
        }
    }
}
