// PopupSearchView.swift
// OpenClip
//
// The action-search palette: a focused text field filtering the full action catalog (enabled and
// disabled) as you type, rendered as one surface with the popup bar. Results appear above or
// below the field depending on popup position; up to 3 rows visible, scrollable beyond that.
// Rows are chosen with the arrows + Return, the mouse, or ⌘1…⌘9 — the first nine rows carry a
// shortcut (shown on the row) that runs them outright. The keys live on the focused field, so
// they exist only while the palette is open.
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

    @Environment(\.popupEffectiveTheme) private var environmentEffectiveTheme
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
        if !environmentEffectiveTheme.isEmpty {
            return environmentEffectiveTheme
        }
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

    /// Height of the search palette card: fits PopupMetrics.searchMaxRows with spacing,
    /// plus insets for the floating search bar so results scroll behind it cleanly.
    private var cardHeight: CGFloat {
        CGFloat(PopupMetrics.searchMaxRows) * PopupMetrics.searchResultRowHeight +
        CGFloat(max(0, PopupMetrics.searchMaxRows - 1)) * 2.0 + 56.0
    }

    public init(
        catalog: [any Action],
        context: ActionContext,
        resultsAbove: Bool = false,
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
        ZStack(alignment: .top) {
            resultsList

            topBlurOverlay
                .frame(maxWidth: .infinity, alignment: .top)

            searchFieldRow
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: PopupMetrics.searchPanelContentWidth, height: cardHeight)
        .background(CommandDigitCatcher { row in runRow(at: row - 1) })
        .popupCardChrome(cornerRadius: PopupMetrics.searchCornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme)
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

    private var cardBackgroundColor: Color {
        if effectiveTheme == "glass" {
            return colorScheme == .dark ? Color.black.opacity(0.40) : Color.white.opacity(0.45)
        } else {
            return Color(red: colorScheme == .dark ? 0.18 : 0.94,
                         green: colorScheme == .dark ? 0.18 : 0.94,
                         blue: colorScheme == .dark ? 0.20 : 0.96)
        }
    }

    private var topBlurOverlay: some View {
        let bg = cardBackgroundColor
        return LinearGradient(
            stops: [
                .init(color: bg, location: 0.0),
                .init(color: bg.opacity(0.85), location: 0.55),
                .init(color: bg.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 52)
        .allowsHitTesting(false)
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
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
            .focused($isFocused)
            .onSubmit { runSelected() }
            .onKeyPress { press in
                // Attached to the focused field: Escape drops the scope (or exits search),
                // up/down move the result selection. ⌘-digits never arrive here — a
                // command-modified key is dispatched through `performKeyEquivalent` and never
                // reaches `keyDown:` — so those live in `CommandDigitCatcher` below.
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
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(isEscHovered ? PopupThemeModel.restForeground(for: effectiveTheme) : PopupThemeModel.restSecondary(for: effectiveTheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        isEscHovered ? Color.primary.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isEscHovered ? Color.primary.opacity(0.25) : Color.secondary.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Exit search")
            .searchHoverTarget(.esc)
            .onHover { hovering in
                useLocalHoverFallback(for: .esc, isHovering: hovering)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(searchFieldBackground)
    }

    private var searchFieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        let darkTint = Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06)
        let shadow1 = Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14)
        let shadow2 = Color.black.opacity(colorScheme == .dark ? 0.12 : 0.06)

        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(darkTint))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
            .shadow(color: shadow1, radius: 6, x: 0, y: 2.5)
            .shadow(color: shadow2, radius: 1, x: 0, y: 0.5)
    }

    /// Closes the palette by dropping the scope back to the full list (Esc with an empty scoped
    /// query) or, when already flat, exiting search entirely.
    private func exitSearch() {
        if scope != nil { onExitScope() } else { onExit() }
    }

    /// Leading field icon: the scope parent's icon when scoped, otherwise the palette's ⌘ glyph.
    private var searchIcon: some View {
        let iconColor = colorScheme == .dark ? Color.white : Color.black
        if let parent = scope?.parent {
            return AnyView(actionIcon(parent).foregroundColor(iconColor))
        } else {
            return AnyView(
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(iconColor)
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
                    .frame(maxWidth: .infinity, minHeight: cardHeight - 56)
                    .padding(.top, 48)
                    .padding(.bottom, 8)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            resultRow(item: item, index: index)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 48)
                    .padding(.bottom, 8)
                }
            }
            .frame(height: cardHeight)
            .onChange(of: selectedIndex) { _, newValue in
                guard scrollSelectionOnKeyboard else { return }
                scrollSelectionOnKeyboard = false
                guard newValue < results.count else { return }
                proxy.scrollTo(results[newValue].id)
            }
        }
    }

    private var selectionHighlightFill: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }

    private var selectionHighlightBorder: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    @ViewBuilder
    private func resultRow(item: ActionSearchIndex, index: Int) -> some View {
        // Hover moves the selection (Spotlight-style), so exactly one row is highlighted:
        // `selectedIndex` is updated by the hover path before this is recomputed.
        let isSelected = index == selectedIndex
        let isHovered = hoveredTarget == .row(index)
        let rowShape = RoundedRectangle(cornerRadius: PopupMetrics.searchRowCornerRadius, style: .continuous)

        Button {
            selectedIndex = index
            runSelected()
        } label: {
            HStack(spacing: 10) {
                iconView(for: rowIcon(for: item.action))
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(
                        isSelected
                            ? .primary
                            : PopupThemeModel.restForeground(for: effectiveTheme)
                    )

                Text(item.title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(
                        isSelected
                            ? .primary
                            : PopupThemeModel.restForeground(for: effectiveTheme)
                    )

                Spacer(minLength: 8)

                if let badge = badgeText(for: item.action) {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(
                            isSelected
                                ? PopupThemeModel.restForeground(for: effectiveTheme)
                                : PopupThemeModel.restSecondary(for: effectiveTheme)
                        )
                }

                if let shortcut = Self.shortcutHint(forRow: index) {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(
                            isSelected
                                ? PopupThemeModel.restForeground(for: effectiveTheme)
                                : PopupThemeModel.restSecondary(for: effectiveTheme)
                        )
                        .accessibilityLabel("Command \(index + 1)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: PopupMetrics.searchResultRowHeight)
            .background(
                Group {
                    if isSelected {
                        rowShape
                            .fill(selectionHighlightFill)
                            .overlay(
                                rowShape.stroke(selectionHighlightBorder, lineWidth: 0.5)
                            )
                    } else if isHovered {
                        rowShape
                            .fill(Color.primary.opacity(0.06))
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(rowShape)
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

    /// How many rows carry a ⌘-digit shortcut: ⌘1…⌘9. Rows past the ninth have none — ⌘0 is not
    /// a tenth row, it is simply unhandled.
    static let maxShortcutRows = 9

    /// The 1-based row a ⌘-digit event points at, or nil when the event is not one. Pure, so the
    /// modifier rules are testable without a window: exactly Command (⌥/⇧/⌃ combinations are
    /// somebody else's shortcut), and a single digit 1...9.
    static func commandDigitRow(for event: NSEvent) -> Int? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad, .help])
        guard modifiers == .command else { return nil }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
              let digit = characters.first?.wholeNumberValue,
              (1...maxShortcutRows).contains(digit) else { return nil }
        return digit
    }

    /// The shortcut label for a row, or nil past the ninth.
    static func shortcutHint(forRow index: Int) -> String? {
        guard index >= 0, index < maxShortcutRows else { return nil }
        return "⌘\(index + 1)"
    }

    /// Runs the row a ⌘-digit points at. Returns false when there is no such row, so the keystroke
    /// falls through to the field (⌘5 in a three-result list types nothing and does nothing)
    /// instead of being silently swallowed.
    private func runRow(at index: Int) -> Bool {
        guard index >= 0, index < Self.maxShortcutRows, results.indices.contains(index) else { return false }
        selectedIndex = index
        runSelected()
        return true
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
    static func buildIndex(
        catalog: [any Action],
        scope: SearchScope?,
        usageRecency: [String: Int],
        presenter: any ActionPresenting,
        aliases: [String: String] = ActionBindingStore.shared.aliases
    ) -> [ActionSearchIndex] {
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
                    usageRecency: usageRecency[action.id] ?? 0,
                    alias: aliases[action.id] ?? ""
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


// MARK: - ⌘-digit Key Equivalents

/// Holds the palette's ⌘1…⌘9 row runner. The handler is refreshed on every SwiftUI update, so it
/// always runs against the current result list — which is why the runner lives in an AppKit view
/// the controller can find (`PopupWindowController.runPaletteRow`) rather than in a closure
/// captured out of a SwiftUI `View` struct, where the `@State` results would go stale.
///
/// It also answers `performKeyEquivalent`, which covers the case where OpenClip *is* the active
/// app and AppKit runs its key-equivalent phase normally. That phase never runs for the popup's
/// non-activating panel, which is why `PaletteRowShortcuts` exists — see that file for the
/// routing story.
struct CommandDigitCatcher: NSViewRepresentable {
    /// Runs the 1-based row, returning false when there is none (the event then falls through).
    let onRow: @MainActor (Int) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRow = onRow
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRow = onRow
    }

    final class CatcherView: NSView {
        var onRow: (@MainActor (Int) -> Bool)?

        /// Runs a 1-based row directly, for the global ⌘-digit hot keys — those never arrive as
        /// events in this process, so there is no key equivalent to walk.
        @MainActor
        func run(row: Int) -> Bool {
            onRow?(row) ?? false
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard let row = PopupSearchView.commandDigitRow(for: event) else {
                return super.performKeyEquivalent(with: event)
            }
            // Claimed whether or not a row exists: while the palette is on screen ⌘1…⌘9 are its
            // own, so ⌘5 in a three-row list quietly does nothing instead of beeping or reaching
            // the app underneath.
            MainActor.assumeIsolated { _ = onRow?(row) }
            return true
        }
    }
}
