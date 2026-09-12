// PopupSearchView.swift
// OpenClip
//
// The action-search palette: a focused text field filtering the full action catalog (enabled and
// disabled) as you type, rendered as one surface with the popup bar. Results appear above or
// below the field depending on popup position; up to 3 rows visible, scrollable beyond that.
// Rows are chosen with the arrows + Return, the mouse, or ⌘1…⌘9 — the first nine rows carry a
// shortcut (shown on the row) that runs them outright. The keys live on the focused field, so
// they exist only while the palette is open. The palette's right edge, bottom edge and corner grip
// are resize handles (`PopupResizeHandles`); the size they settle on is remembered and, passed
// back in as `maxSize`, caps the palette on the next entry: a couple of results still get a short
// palette, a long list grows up to the maximum and scrolls beyond it. Once the user has dragged a
// handle (`isUserSized`), the palette keeps the dragged size verbatim until it closes.
// A query that matches nothing is not a dead end: while AI is on, the empty state offers the
// typed text as an AI instruction — "Ask AI" runs it once on the selection, "Save as AI tool"
// keeps it as a custom AI preset (a searchable action from then on) and runs it. Recent
// instructions are ordinary rows of the catalog (`RecentPromptAction`), found by typing any part
// of them. For all of these, ⏎ / click / ⌘-digit show AI's answer in the result card (with the
// diff) and ⇧⏎ / ⇧-click paste it over the selection (see `PaletteAIPrompt`).
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
    /// Runs an instruction on the selection (or standalone without context if includeContext is false).
    /// The flag is true to paste the answer over the selection (⇧⏎, ⇧-click) and
    /// false to show the result card first (⏎, click, ⌘-digit).
    public let onRunAIPrompt: @MainActor (String, Bool, Bool) -> Void
    /// Saves the typed query as a reusable AI tool and runs it — the "Save as AI tool" row. Same
    /// flag as `onRunAIPrompt`.
    public let onSaveAIPrompt: @MainActor (String, Bool) -> Void
    /// Whether AI is switched on; off, the empty state keeps its plain "No matches" copy.
    private let isAIEnabled: Bool
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
    /// The most room the palette may take — the user's remembered or in-progress resize. The
    /// palette renders at what its results need up to this; `nil` caps at the default column
    /// (`searchPanelContentWidth` wide, `searchMaxRows` rows tall).
    public let maxSize: CGSize?
    /// True once the user has dragged a resize handle of this palette: it then renders at
    /// `maxSize` verbatim — the size they set, whatever the results need — instead of the
    /// content-fitted size.
    public let isUserSized: Bool
    /// Reports a drag of one of the resize handles so the owner can resize the panel and remember
    /// the size. `.began` is reported exactly once per drag.
    public let onResize: @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool
    /// Set by keyboard selection moves so `.onChange` auto-scrolls the list; hover-driven
    /// selection changes leave it false so hovering the edge of a row never shifts the list.
    @State private var scrollSelectionOnKeyboard = false
    @State private var isCommandPressed: Bool = false
    @State private var localFlagsMonitor: Any?
    @State private var globalFlagsMonitor: Any?
    @ObservedObject private var modeStore: PopupModeStore

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
    private let hoverState: PopupHoverState
    /// True for the Appearance page's preview: the palette draws and filters as it would live,
    /// but never takes focus on its own, installs no event monitors, offers no resize handles and
    /// runs nothing — Return, a row click and the footer badges are inert.
    private let isStatic: Bool
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

    /// Height of the search palette card: what the current results need (field inset, rows,
    /// spacing, bottom padding), never shorter than `searchPaletteMinHeight` and never taller than
    /// the maximum — the remembered size, or `defaultHeight` (`searchMaxRows` rows) — beyond which
    /// the list scrolls. Once user-sized it is exactly the dragged size.
    private var cardHeight: CGFloat {
        if isUserSized, let maxSize { return maxSize.height }
        return Self.bounded(naturalHeight, min: PopupMetrics.searchPaletteMinHeight, max: maxSize?.height ?? Self.defaultHeight)
    }

    /// Width of the search palette card. The default column is the floor — a list has a design
    /// width, and rows only widen it when a title needs the room — capped by the maximum (the
    /// remembered width, or the default column). Once user-sized it is exactly the dragged size.
    private var cardWidth: CGFloat {
        if isUserSized, let maxSize { return maxSize.width }
        let needed = max(PopupMetrics.searchPanelContentWidth, naturalRowWidth)
        return Self.bounded(needed, min: PopupMetrics.searchPaletteMinWidth, max: maxSize?.width ?? PopupMetrics.searchPanelContentWidth)
    }

    /// The field's floating inset the rows scroll behind.
    private static let fieldInset: CGFloat = 56.0
    private static let rowSpacing: CGFloat = 2.0
    private static let listBottomPadding: CGFloat = 8.0

    /// What the list needs to show every current row without scrolling.
    private var naturalHeight: CGFloat {
        Self.height(forRows: rowCount) + (promptRows.isEmpty ? 0 : Self.footerOverlayHeight)
    }

    /// The AI rows under the results for the current query: Ask + Save when nothing matched, none otherwise.
    private var promptRows: [PaletteAIPromptRow] {
        PaletteAIPrompt.rows(for: query, aiEnabled: isAIEnabled, results: results.isEmpty ? .none : .actions)
    }

    /// The selectable rows on screen — the results followed by the AI rows. Every keyboard, hover
    /// and ⌘-digit path indexes against this, so the AI rows are reached exactly like results.
    private var rowCount: Int {
        results.count + promptRows.count
    }

    private static let footerOverlayHeight: CGFloat = 28.0

    static func height(forRows rows: Int) -> CGFloat {
        fieldInset + CGFloat(rows) * PopupMetrics.searchResultRowHeight
            + CGFloat(max(0, rows - 1)) * rowSpacing + listBottomPadding
    }

    /// The palette's default maximum height: `searchMaxRows` rows behind the field. Internal for tests.
    static var defaultHeight: CGFloat {
        CGFloat(PopupMetrics.searchMaxRows) * PopupMetrics.searchResultRowHeight +
        CGFloat(max(0, PopupMetrics.searchMaxRows - 1)) * rowSpacing + fieldInset
    }

    /// The widest row among the current results — icon column, title, spacer and shortcut hint
    /// with their paddings. Measured once per result set, never per body evaluation.
    @State private var naturalRowWidth: CGFloat = 0

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let shortcutFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    static func naturalRowWidth(for results: [ActionSearchIndex]) -> CGFloat {
        // Row chrome: list padding 8+8, row padding 10+10, icon column 18, icon→title spacing 10,
        // the spacer's minimum 8, and title→shortcut spacing 10 when the row carries a shortcut.
        let shortcutWidth = ceil(("⌘9" as NSString).size(withAttributes: [.font: shortcutFont]).width)
        var widest: CGFloat = 0
        for (index, item) in results.enumerated() {
            let title = ceil((item.title as NSString).size(withAttributes: [.font: titleFont]).width)
            var width = 16 + 20 + 18 + 10 + title + 8
            if shortcutHint(forRow: index) != nil {
                width += 10 + shortcutWidth
            }
            widest = max(widest, width)
        }
        // A point of slack so SwiftUI's own layout never truncates the measured title.
        return widest + 1
    }

    private static func bounded(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(maximum, minimum))
    }

    private static var prewarmedIndexCache: (catalogIDs: [String], usageRecency: [String: Int], index: [ActionSearchIndex])?

    public static func prewarmIndex(catalog: [any Action]) {
        let recency = ActionUsageStore.shared.recency
        let index = buildIndex(
            catalog: catalog,
            scope: nil,
            usageRecency: recency,
            presenter: ActionCustomizationManager.shared
        )
        prewarmedIndexCache = (catalog.map(\.id), recency, index)
    }

    public init(
        catalog: [any Action],
        context: ActionContext,
        resultsAbove: Bool = false,
        presenter: any ActionPresenting = ActionCustomizationManager.shared,
        modeStore: PopupModeStore = PopupModeStore(),
        scope: SearchScope? = nil,
        usageRecency: [String: Int] = [:],
        maxSize: CGSize? = nil,
        isUserSized: Bool = false,
        onResize: @escaping @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void = { _, _ in },
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onExit: @escaping @MainActor () -> Void,
        onExitScope: @escaping @MainActor () -> Void = {},
        onRunAI: @escaping @MainActor (String) -> Void = { _ in },
        onRunAIPrompt: @escaping @MainActor (String, Bool, Bool) -> Void = { _, _, _ in },
        onSaveAIPrompt: @escaping @MainActor (String, Bool) -> Void = { _, _ in },
        aiEnabled: Bool = AIServiceManager.shared.isAIEnabled,
        onActionPerformed: (@MainActor (String) -> Void)? = nil,
        onWillPerformAction: (@MainActor (any Action) -> Void)? = nil,
        onRunLoadingAction: (@MainActor (any Action) -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary },
        hoverState: PopupHoverState = .shared,
        isStatic: Bool = false
    ) {
        self.catalog = catalog
        self.hoverState = hoverState
        self.isStatic = isStatic
        self.context = context
        self.resultsAbove = resultsAbove
        self.presenter = presenter
        self._modeStore = ObservedObject(wrappedValue: modeStore)
        self.scope = scope
        self.usageRecency = usageRecency
        self.maxSize = maxSize
        self.isUserSized = isUserSized
        self.onResize = onResize
        self.onResult = onResult
        self.onExit = onExit
        self.onExitScope = onExitScope
        self.onRunAI = onRunAI
        self.onRunAIPrompt = onRunAIPrompt
        self.onSaveAIPrompt = onSaveAIPrompt
        self.isAIEnabled = aiEnabled
        self.onActionPerformed = onActionPerformed
        self.onWillPerformAction = onWillPerformAction
        self.onRunLoadingAction = onRunLoadingAction
        self.onClickIntent = onClickIntent
        // Index once at entry: the palette is recreated on every search entry (mode + scope
        // transition together), so the current catalog/scope are captured here. If a prewarmed
        // index matches the current catalog and recency, reuse it for instant appearance; otherwise build fresh.
        let initialIndex: [ActionSearchIndex]
        if scope == nil,
           let prewarmed = Self.prewarmedIndexCache,
           prewarmed.catalogIDs == catalog.map(\.id),
           prewarmed.usageRecency == usageRecency {
            initialIndex = prewarmed.index
        } else {
            initialIndex = Self.buildIndex(catalog: catalog, scope: scope, usageRecency: usageRecency, presenter: presenter)
        }
        _searchIndex = State(initialValue: initialIndex)
        _results = State(initialValue: initialIndex)
        _naturalRowWidth = State(initialValue: Self.naturalRowWidth(for: initialIndex))
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

            if rowCount > 0 {
                bottomBlurOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                footerOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if !isStatic {
                PopupResizeHandles(
                    tint: PopupThemeModel.restForeground(for: effectiveTheme),
                    accessibilityLabel: String(localized: "Resize search palette"),
                    onResize: onResize
                )
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background {
            if !isStatic {
                CommandDigitCatcher { row in runRow(at: row - 1) }
            }
        }
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
            naturalRowWidth = Self.naturalRowWidth(for: results)
            selectedIndex = 0
        }
        .onChange(of: scope?.parent.id) { _, _ in
            rebuildSearchIndex()
        }
        .onAppear {
            guard !isStatic else { return }
            isFocused = true
            isCommandPressed = NSEvent.modifierFlags.contains(.command)
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isCommandPressed = event.modifierFlags.contains(.command)
                return event
            }
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                isCommandPressed = event.modifierFlags.contains(.command)
            }
        }
        .onDisappear {
            if let local = localFlagsMonitor {
                NSEvent.removeMonitor(local)
                localFlagsMonitor = nil
            }
            if let global = globalFlagsMonitor {
                NSEvent.removeMonitor(global)
                globalFlagsMonitor = nil
            }
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

    private var bottomBlurOverlay: some View {
        let bg = cardBackgroundColor
        return LinearGradient(
            stops: [
                .init(color: bg.opacity(0.0), location: 0.0),
                .init(color: bg.opacity(0.85), location: 0.45),
                .init(color: bg, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 48)
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
            .onSubmit { runSelected(replace: NSEvent.modifierFlags.contains(.shift)) }
            .onKeyPress { press in
                // Attached to the focused field: Escape drops the scope (or exits search),
                // up/down move the result selection, Return runs the row (⇧ asks for the in-place
                // replacement instead of the result card on AI rows). ⌘-digits never arrive
                // here — a command-modified key is dispatched through `performKeyEquivalent` and
                // never reaches `keyDown:` — so those live in `CommandDigitCatcher` below.
                if press.key == .escape {
                    exitSearch()
                    return .handled
                }
                if press.key == .return {
                    runSelected(replace: press.modifiers.contains(.shift))
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
        guard !isStatic else { return }
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
                if results.isEmpty, promptRows.isEmpty {
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
                        // The AI rows follow the results (Ask + Save when nothing matched, Save
                        // alone after recent-prompt matches).
                        ForEach(Array(promptRows.enumerated()), id: \.element) { offset, row in
                            promptRow(row, index: results.count + offset)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 48)
                    .padding(.bottom, 38)
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
            runSelected(replace: NSEvent.modifierFlags.contains(.shift))
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

                if item.action.chrome.isInlineResult, let result = modeStore.inlineResults[item.action.id], !isCommandPressed {
                    Text(result)
                        .font(.system(size: 11, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: PopupMetrics.inlineSearchAccessoryMaxWidth, alignment: .trailing)
                        .foregroundColor(
                            isSelected
                                ? PopupThemeModel.restForeground(for: effectiveTheme)
                                : PopupThemeModel.restSecondary(for: effectiveTheme)
                        )
                        .transition(.opacity)
                } else if let shortcut = Self.shortcutHint(forRow: index) {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(
                            isSelected
                                ? PopupThemeModel.restForeground(for: effectiveTheme)
                                : PopupThemeModel.restSecondary(for: effectiveTheme)
                        )
                        .transition(.opacity)
                        .accessibilityLabel("Command \(index + 1)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: PopupMetrics.searchResultRowHeight)
            .animation(.easeInOut(duration: PopupMetrics.inlineCrossFadeDuration), value: isCommandPressed)
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

    /// One AI fallback row — the same chrome as a result row (icon column, title, ⌘-digit hint,
    /// selection/hover fills) so the empty state reads as two more things to run, not a notice.
    @ViewBuilder
    private func promptRow(_ row: PaletteAIPromptRow, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let isHovered = hoveredTarget == .row(index)
        let rowShape = RoundedRectangle(cornerRadius: PopupMetrics.searchRowCornerRadius, style: .continuous)
        let foreground = isSelected ? Color.primary : PopupThemeModel.restForeground(for: effectiveTheme)
        let title = PaletteAIPrompt.rowTitle(row, query: query)

        Button {
            selectedIndex = index
            runSelected(replace: NSEvent.modifierFlags.contains(.shift))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: PaletteAIPrompt.rowSymbol(row))
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(foreground)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foreground)

                Spacer(minLength: 8)

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
                            .overlay(rowShape.stroke(selectionHighlightBorder, lineWidth: 0.5))
                    } else if isHovered {
                        rowShape.fill(Color.primary.opacity(0.06))
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .searchHoverTarget(.row(index))
        .onHover { hovering in
            useLocalHoverFallback(for: .row(index), isHovering: hovering)
        }
    }

    private var isSelectedAI: Bool {
        if selectedIndex >= results.count {
            return true
        }
        guard results.indices.contains(selectedIndex) else { return false }
        return ActionIdentity.isAIPreset(results[selectedIndex].action)
    }

    /// The action badges overlay at the bottom of the palette.
    private var footerOverlay: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)

            if rowCount > 0 {
                if isSelectedAI {
                    hintBadge(
                        title: PaletteAIPrompt.secondaryActionTitle(canPaste: modeStore.canPaste),
                        shortcut: "⇧⏎",
                        isAccent: false
                    ) {
                        runSelected(replace: true)
                    }

                    hintBadge(
                        title: PaletteAIPrompt.primaryActionTitle(),
                        shortcut: "⏎",
                        isAccent: true
                    ) {
                        runSelected(replace: false)
                    }
                } else {
                    hintBadge(
                        title: "",
                        shortcut: "⇧⏎",
                        isAccent: false
                    ) {
                        runSelected(replace: true)
                    }

                    hintBadge(
                        title: String(localized: "Run"),
                        shortcut: "⏎",
                        isAccent: true
                    ) {
                        runSelected(replace: false)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(height: Self.footerOverlayHeight)
        .animation(.easeInOut(duration: 0.15), value: isSelectedAI)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func hintBadge(title: String, shortcut: String, isAccent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11, weight: isAccent ? .semibold : .medium))
                        .foregroundColor(isAccent ? .white : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                }
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isAccent ? .white.opacity(0.9) : PopupThemeModel.restSecondary(for: effectiveTheme))
            }
            .padding(.horizontal, title.isEmpty ? 7 : 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isAccent ? Color.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isAccent ? Color.white.opacity(0.18) : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func moveSelection(by delta: Int) {
        guard rowCount > 0 else { return }
        let newIndex = min(max(selectedIndex + delta, 0), rowCount - 1)
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
        guard index >= 0, index < Self.maxShortcutRows, index < rowCount else { return false }
        selectedIndex = index
        runSelected(replace: false)
        return true
    }

    /// Runs the highlighted row. `replace` only matters for AI rows (Ask, Save, recents): false
    /// (⏎, click, ⌘-digit) shows the result card first, true (⇧⏎, ⇧-click) pastes the answer
    /// over the selection.
    private func runSelected(replace: Bool) {
        guard !isStatic else { return }
        if selectedIndex >= results.count {
            // The AI rows: the typed query is the instruction.
            let offset = selectedIndex - results.count
            guard promptRows.indices.contains(offset) else { return }
            let instruction = PaletteAIPrompt.instruction(from: query)
            switch promptRows[offset] {
            case .apply: onRunAIPrompt(instruction, replace, true)
            case .ask: onRunAIPrompt(instruction, replace, false)
            case .save: onSaveAIPrompt(instruction, replace)
            }
            return
        }
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
        if action.chrome.isInlineResult {
            if let result = modeStore.inlineResults[action.id] {
                onResult(.text(result))
                return
            } else if let inFlight = InlineResultEvaluator.shared.runningTask(for: action.id) {
                Task { @MainActor in
                    do {
                        if let text = await inFlight.value, !text.isEmpty {
                            onResult(.text(text))
                            return
                        }
                        let match = action.matchInfo(for: context)
                        let performContext = ActionContext(
                            selection: context.selection,
                            modifiers: context.modifiers,
                            isSecondaryClick: replace || onClickIntent() == .secondary,
                            match: match
                        )
                        let result = try await action.perform(performContext)
                        onResult(result)
                    } catch {
                        onResult(.toast(StatusFeedback(error: error)))
                    }
                }
                return
            }
        }
        Task { @MainActor in
            do {
                // Same match plumbing as the bar's perform path: thread the visibility match into
                // the perform context so placeholders/env see the same match that enabled the row.
                let match = action.matchInfo(for: context)
                let performContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: replace || onClickIntent() == .secondary,
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
        naturalRowWidth = Self.naturalRowWidth(for: results)
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
        if case .row(let index) = target, index < rowCount {
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
            if case .row(let index) = target, index < rowCount {
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
