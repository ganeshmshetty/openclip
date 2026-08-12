// CanvasSessionView.swift
// OpenClip
//
// The surface for the single active content-canvas session (Task 12): the chrome CanvasHeaderView
// plus a scrollable CanvasComponentView body, ordered by `searchResultsAbove` (header pinned near
// the cursor when the popup sits at the bottom of the screen), inside the glass/classic card
// surface ported from PopupContentView.cardContainer. Owns the renderer-facing focus plumbing —
// `focusID`/`rootFocused` @FocusState re-applied from `session.focusedComponentID` on every
// `focusGeneration` bump — the Esc key that exits content, and the text-field draft edit buffer
// (the field just left is committed as a `.change` event; drafts for non-focused fields are
// dropped on every tree re-render, and a slow dispatch that moves focus can't lose the typed value
// because the tree re-render flushes the field being left *before* dropping — drop-after-commit,
// see `CanvasSessionDraftPlan`). Sizing follows §7.1: the width column min/ideal/max comes
// from CanvasLimits clamped to the screen, the body scroll box is capped at
// `PopupMetrics.popupMaxHeight - PopupMetrics.canvasHeaderHeight`, and a producer-set
// `preferredSize` is fixed for the session.
import SwiftUI
import AppKit
import Core

/// The root focus id: when `session.focusedComponentID` is nil the canvas root takes focus
/// (`rootFocused = true`). Task 14 wires key-mode; kept as a named constant for that wiring.
let kRootFocusID = "__canvas_root__"

@MainActor
public struct CanvasSessionView: View {
    @ObservedObject public var session: CanvasSession
    /// When true (popup sits at the bottom of the screen) the chrome header renders at the
    /// card's bottom edge — near the cursor — and the canvas body grows upward above it,
    /// mirroring how the search palette keeps its field fixed and grows results above.
    public let searchResultsAbove: Bool
    public let onExitContent: () -> Void
    public let onEvent: (CanvasEvent) -> Void
    public let onEffect: (CanvasEffect) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @FocusState private var focusID: String?
    @FocusState private var rootFocused: Bool
    /// Edit buffer for text-field drafts. Not a value store: the tree's `props.value` is
    /// authoritative after a dispatch; drafts exist only while a field is being edited.
    @State private var fieldDrafts: [String: String] = [:]
    /// Fields whose draft was already flushed as a `.change` by the blur (`focusID`) handler in the
    /// current update cycle. Prevents the racing tree re-render handler from committing the same
    /// field twice (a blur commit keeps the draft so the typed text stays visible until the
    /// engine's tree lands, so without the set the drop-after-commit pass would re-ship it).
    @State private var committedDrafts: Set<String> = []
    @State private var measuredContentHeight: CGFloat = 0
    private let hoverState: PopupHoverState = .shared

    public init(
        session: CanvasSession,
        searchResultsAbove: Bool,
        onExitContent: @escaping () -> Void,
        onEvent: @escaping (CanvasEvent) -> Void,
        onEffect: @escaping (CanvasEffect) -> Void
    ) {
        self.session = session
        self.searchResultsAbove = searchResultsAbove
        self.onExitContent = onExitContent
        self.onEvent = onEvent
        self.onEffect = onEffect
    }

    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var effectiveTheme: String {
        let category = PopupThemeModel.category(fromStored: selectedTheme)
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    public var body: some View {
        surface
            .coordinateSpace(name: "popupHoverSpace")
            .id(session.id)                                  // wholesale replace on new mount
            .onChange(of: session.focusGeneration) { _, _ in
                Task { @MainActor in await Task.yield(); applyFocus() }
            }
            .onChange(of: session.tree) { oldTree, _ in
                // Drop-after-commit for non-focused drafts. A dispatch re-render and a focus move
                // can land in the same update cycle with no guaranteed `.onChange` ordering: if the
                // tree publish is observed before the `@FocusState` flip, `focusID` already names
                // the NEW target, and a plain drop here would delete the field we just left before
                // the blur commit (`.onChange(of: focusID)`) ran — losing the typed value. So flush
                // each non-focused draft as a `.change` before dropping it; the blur commit that may
                // fire afterwards is then a no-op (its draft is gone). The handler is resolved
                // against the OLD tree, which still owns the field being dropped. The still-focused
                // field keeps its draft — in-progress typing survives an unrelated dispatch.
                let focused = focusID
                let plan = CanvasSessionDraftPlan.plan(
                    drafts: fieldDrafts,
                    committed: committedDrafts,
                    focused: focused,
                    tree: oldTree
                )
                for commit in plan.commits {
                    commitDraft(commit.id, value: commit.value, in: oldTree)
                }
                fieldDrafts = plan.survivingDrafts
                committedDrafts.removeAll()
            }
            .onAppear { Task { @MainActor in await Task.yield(); applyFocus() } }
            .onChange(of: focusID) { old, _ in
                // Commit the field we just left (blur-triggered change, never per-keystroke). The
                // draft is kept so the typed text stays visible until the engine's tree lands (the
                // tree re-render drop cleans it up later); `committedDrafts` stops a racing
                // tree-change in the same update cycle from shipping the same value twice.
                if let old {
                    commitDraft(old, value: fieldDrafts[old], in: session.tree)
                    committedDrafts.insert(old)
                }
            }
    }

    // MARK: - Surface

    private var surface: some View {
        applySurfaceStyle(sizedSurface)
            .environment(\.colorScheme, effectiveColorScheme)
    }

    /// §7.1 sizing: a producer-set `preferredSize` renders the surface at that size (clamped to the
    /// width column and the popup height cap, and never below the fixed header height), fixed for
    /// the session; nil → fitting-size column.
    @ViewBuilder
    private var sizedSurface: some View {
        if let size = session.preferredSize {
            headerAndBody
                .frame(width: min(size.width, clampedWidths.max),
                       height: min(max(size.height, PopupMetrics.canvasHeaderHeight), PopupMetrics.popupMaxHeight))
        } else {
            headerAndBody
                .frame(minWidth: clampedWidths.min,
                       idealWidth: clampedWidths.ideal,
                       maxWidth: clampedWidths.max)
        }
    }

    @ViewBuilder
    private var headerAndBody: some View {
        let header = CanvasHeaderView(
            title: session.header.title,
            icon: session.header.icon,
            onBack: onExitContent,
            searchResultsAbove: searchResultsAbove,
            hoverState: hoverState
        )
        let bodyView = bodyScroll
        if searchResultsAbove {
            VStack(spacing: 0) {
                bodyView
                    .frame(maxHeight: .infinity, alignment: .bottom)
                header
            }
        } else {
            VStack(spacing: 0) {
                header
                bodyView
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// The scrollable canvas body. `.frame(maxHeight: PopupMetrics.popupMaxHeight - PopupMetrics.canvasHeaderHeight)`:
    /// the header chrome fills 33pt above/below the body scroll box; the panel's resizePanel still
    /// caps the whole surface at PopupMetrics.popupMaxHeight (240) — the single sizing funnel.
    private var bodyContent: some View {
        CanvasComponentView(
            tree: session.tree,
            focusID: $focusID,
            fieldDrafts: $fieldDrafts,
            onEvent: onEvent,
            onEffect: onEffect,
            onExitContent: onExitContent
        )
        .padding(12)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: CanvasContentSizeKey.self, value: proxy.size.height)
            }
        )
    }

    private var bodyScroll: some View {
        let availableBodyHeight = session.preferredSize.map {
            min(max($0.height, PopupMetrics.canvasHeaderHeight), PopupMetrics.popupMaxHeight) - PopupMetrics.canvasHeaderHeight
        }
            ?? (PopupMetrics.popupMaxHeight - PopupMetrics.canvasHeaderHeight)
        let needsScroll = measuredContentHeight > availableBodyHeight
        return Group {
            if needsScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    bodyContent
                }
                .frame(height: availableBodyHeight)
            } else {
                bodyContent
            }
        }
        .onPreferenceChange(CanvasContentSizeKey.self) { height in
            if height > 0 {
                measuredContentHeight = height
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onKeyPress(.escape) { onExitContent(); return .handled }
        .accessibilityElement(children: .contain)
    }

    /// Width column from CanvasLimits, clamped to the screen's visible frame minus the popup's
    /// horizontal padding so a narrow display never exceeds it.
    private var clampedWidths: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let width = screen?.visibleFrame.width else {
            return (CanvasLimits.canvasMinWidth, CanvasLimits.canvasIdealWidth, CanvasLimits.canvasMaxWidth)
        }
        let available = width - 2 * PopupMetrics.popupPadding
        return (min(CanvasLimits.canvasMinWidth, available),
                min(CanvasLimits.canvasIdealWidth, available),
                min(CanvasLimits.canvasMaxWidth, available))
    }

    /// Glass/classic card surface ported from PopupContentView.cardContainer. On macOS 26 the
    /// glass layer uses `.clear` so its elevation shadow doesn't clip on the large surface; the
    /// material supplies the frost and a SwiftUI `.shadow` provides the elevation.
    @ViewBuilder
    private func applySurfaceStyle(_ content: some View) -> some View {
        let cornerRadius: CGFloat = 10
        if effectiveTheme == "glass" {
            if #available(macOS 26, *) {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1.0)
                    )
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .compositingGroup()
                    .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
            }
        } else {
            let bgFill = effectiveTheme == "dark"
                ? Color(red: 0.20, green: 0.20, blue: 0.22)
                : Color(red: 0.91, green: 0.91, blue: 0.93)
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(bgFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1.0)
                )
                .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
        }
    }

    private var cardBorder: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
    }

    private var shadowOpacity: Double {
        effectiveTheme == "light" ? 0.16 : 0.32
    }

    // MARK: - Focus

    private func applyFocus() {
        if let id = session.focusedComponentID {
            focusID = id            // root focus is only requested with id == nil
        } else {
            rootFocused = true
        }
    }

    /// Ships a field's draft as a `.change` via the field's own `onChange` handler (blur-triggered,
    /// never per-keystroke). Nil handler, unknown field, or absent draft → no-op.
    private func commitDraft(_ fieldID: String, value draft: String?, in tree: CanvasComponent) {
        guard let draft,
              let handler = tree.canvasTextFieldProps(withID: fieldID)?.onChange else { return }
        routeCanvasHandler(handler, kind: .change, value: draft, targetID: fieldID,
                           onEvent: onEvent, onEffect: onEffect)
    }
}

// MARK: - Draft drop-after-commit planning

/// Pure bookkeeping for the session's text-field draft edit buffer, extracted from
/// `CanvasSessionView`'s `.onChange(of: session.tree)` handler (and its `@State`
/// `committedDrafts`) so the drop-after-commit rule is unit-testable without hosting a SwiftUI
/// view or racing two `.onChange` callbacks. A value type: `plan` both of the dispatch-path and
/// the blur-only path through one place. The rule: before the non-focused drafts are dropped, the
/// field being left is flushed as a `.change` (against the OLD tree, which still owns it), so a
/// focus-moving dispatch can't lose the typed value; the still-focused field keeps its draft.
struct CanvasSessionDraftPlan {
    /// One field draft to ship as a `.change` (self-contained so the plan is `Equatable`-wise).
    struct Commit: Equatable {
        let id: String
        let value: String
    }

    /// Drafts to ship as `.change` this pass.
    var commits: [Commit] = []
    /// The draft map after the pass — only the still-focused field's draft survives.
    var survivingDrafts: [String: String] = [:]

    var isEmpty: Bool {
        commits.isEmpty && survivingDrafts.isEmpty
    }

    /// Plans which drafts to flush-and-drop and which to survive for a tree re-render.
    /// - Parameters:
    ///   - drafts: the edit buffer at re-render time.
    ///   - committed: fields whose draft was already flushed by the blur handler this cycle
    ///     (they must NOT be committed a second time).
    ///   - focused: the field currently owning focus (`focusID`).
    ///   - tree: the tree being re-rendered away from — the dropped fields' `.onChange`
    ///     handlers are resolved here, so a field that a dispatch removed still commits.
    static func plan(drafts: [String: String], committed: Set<String>, focused: String?,
                     tree: CanvasComponent) -> CanvasSessionDraftPlan {
        var result = CanvasSessionDraftPlan()
        let fieldMap = tree.textFieldsByID()
        for id in drafts.keys {
            guard id != focused else {
                result.survivingDrafts[id] = drafts[id]
                continue
            }
            if !committed.contains(id),
               let value = drafts[id],
               fieldMap[id]?.onChange != nil {
                result.commits.append(CanvasSessionDraftPlan.Commit(id: id, value: value))
            }
        }
        return result
    }
}

/// Tree helper for the session view: resolves the `CanvasTextFieldProps` for a focus id so the
/// blur commit can reach its `onChange` handler.
fileprivate extension CanvasComponent {
    func textFieldsByID() -> [String: CanvasTextFieldProps] {
        var map: [String: CanvasTextFieldProps] = [:]
        func walk(_ node: CanvasComponent) {
            switch node {
            case .textField(let props):
                map[props.id] = props
            case .stack(_, let children):
                for child in children { walk(child) }
            default:
                break
            }
        }
        walk(self)
        return map
    }
}

private struct CanvasContentSizeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

fileprivate extension CanvasComponent {
    func canvasTextFieldProps(withID id: String) -> CanvasTextFieldProps? {
        textFieldsByID()[id]
    }
}
