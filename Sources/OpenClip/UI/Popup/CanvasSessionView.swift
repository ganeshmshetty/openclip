// CanvasSessionView.swift
// OpenClip
//
// The surface for the single active content-canvas session (Task 12): the chrome CanvasHeaderView
// plus a scrollable CanvasComponentView body, ordered by `searchResultsAbove` (header pinned near
// the cursor when the popup sits at the bottom of the screen), inside the glass/classic card
// surface ported from PopupContentView.cardContainer. Owns the renderer-facing focus plumbing —
// `focusID`/`rootFocused` @FocusState re-applied from `session.focusedComponentID` on every
// `focusGeneration` bump — the Esc key that exits content, and the text-field draft edit buffer
// (drafts dropped for non-focused fields on every tree re-render; the field just left is committed
// as a `.change` event on focus loss). Sizing follows §7.1: the width column min/ideal/max comes
// from CanvasLimits clamped to the screen, the body scroll box is capped at
// `Constants.popupMaxHeight - 36`, and a producer-set `preferredSize` is fixed for the session.
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
            .id(session.id)                                  // wholesale replace on new mount
            .onChange(of: session.focusGeneration) { _, _ in
                Task { @MainActor in await Task.yield(); applyFocus() }
            }
            .onChange(of: session.tree) { _, _ in
                // A dispatch re-render makes the tree authoritative: drop drafts for fields that
                // are no longer the focus target so a changed value re-renders correctly (an
                // external control updating a field's value must not show stale text). The focused
                // field keeps its draft — in-progress typing survives an unrelated dispatch.
                let focused = focusID
                for id in Array(fieldDrafts.keys) where id != focused {
                    fieldDrafts.removeValue(forKey: id)
                }
            }
            .onAppear { Task { @MainActor in await Task.yield(); applyFocus() } }
            .onChange(of: focusID) { old, _ in
                // Commit the field we just left (blur-triggered change, never per-keystroke).
                commitFocusedFieldIfNeeded(old: old)
            }
    }

    // MARK: - Surface

    private var surface: some View {
        applySurfaceStyle(sizedSurface)
            .environment(\.colorScheme, effectiveColorScheme)
    }

    /// §7.1 sizing: a producer-set `preferredSize` renders the surface at that size (clamped to the
    /// width column and the popup height cap), fixed for the session; nil → fitting-size column.
    @ViewBuilder
    private var sizedSurface: some View {
        if let size = session.preferredSize {
            headerAndBody
                .frame(width: min(size.width, clampedWidths.max),
                       height: min(size.height, Constants.popupMaxHeight))
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
            VStack(spacing: 0) { bodyView; header }
        } else {
            VStack(spacing: 0) { header; bodyView }
        }
    }

    /// The scrollable canvas body. `.frame(maxHeight: Constants.popupMaxHeight - 36)`: the header
    /// chrome fills 36pt above the body scroll box; the panel's resizePanel still caps the whole
    /// surface at Constants.popupMaxHeight (240) — the single sizing funnel.
    private var bodyScroll: some View {
        ScrollView(.vertical, showsIndicators: true) {
            CanvasComponentView(
                tree: session.tree,
                focusID: $focusID,
                fieldDrafts: $fieldDrafts,
                onEvent: onEvent,
                onEffect: onEffect,
                onExitContent: onExitContent
            )
        }
        .frame(minHeight: 40, maxHeight: Constants.popupMaxHeight - 36)
        .focusable()
        .focused($rootFocused)
        .onKeyPress(.escape) { onExitContent(); return .handled }
        .accessibilityElement(children: .contain)
    }

    /// Width column from CanvasLimits, clamped to the screen's visible frame minus the popup's
    /// horizontal padding so a narrow display never exceeds it.
    private var clampedWidths: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        guard let width = NSScreen.main?.visibleFrame.width else {
            return (CanvasLimits.canvasMinWidth, CanvasLimits.canvasIdealWidth, CanvasLimits.canvasMaxWidth)
        }
        let available = width - 2 * Constants.popupPadding
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

    /// Commits the text field we just left as a `.change` event (blur-triggered, never
    /// per-keystroke). Nil `onChange` handlers fire no event; the draft already persists in the
    /// edit buffer so the typed value stays visible.
    private func commitFocusedFieldIfNeeded(old fieldID: String?) {
        guard let fieldID, let draft = fieldDrafts[fieldID],
              let handler = session.tree.canvasTextFieldProps(withID: fieldID)?.onChange else { return }
        routeCanvasHandler(handler, kind: .change, value: draft, targetID: fieldID,
                           onEvent: onEvent, onEffect: onEffect)
    }
}

/// Tree helper for the session view: resolves the `CanvasTextFieldProps` for a focus id so the
/// blur commit can reach its `onChange` handler.
fileprivate extension CanvasComponent {
    private var canvasSubnodes: [CanvasComponent] {
        if case .stack(_, let children) = self { return children }
        return []
    }

    func canvasTextFieldProps(withID id: String) -> CanvasTextFieldProps? {
        if case .textField(let props) = self, props.id == id { return props }
        for child in canvasSubnodes {
            if let found = child.canvasTextFieldProps(withID: id) { return found }
        }
        return nil
    }
}
