// CanvasComponentView.swift
// OpenClip
//
// The SwiftUI renderer for a canvas component tree (Task 12): a recursive `CanvasTree` view drives
// all 11 component cases, resolving theme tokens through PopupThemeModel, icons through the app's
// existing pipeline (SF Symbol / IconifySVGView / LocalIconCache / AsyncImage), and routing
// handlers into the session event/effect doors. Focusable nodes carry `.focused` bindings for the
// session's focus plumbing. Text-field drafts live in a session-owned edit buffer threaded down as
// a Binding; the toggle keeps a local `@State` seeded from the tree's authoritative value and
// resynced on every dispatch re-render.
import SwiftUI
import AppKit
import Core

/// Routes a node's handler into the session doors: a `.effect` goes straight to `onEffect`; a
/// `.dispatch(name)` becomes a `CanvasEvent` with the given kind/value/target. Shared by the tree
/// renderer, its interactive subviews, and the session's blur-commit path.
func routeCanvasHandler(_ handler: CanvasHandler, kind: CanvasEvent.Kind, value: String?, targetID: String?,
                        onEvent: (CanvasEvent) -> Void, onEffect: (CanvasEffect) -> Void) {
    switch handler {
    case .effect(let effect):
        onEffect(effect)
    case .dispatch(let name):
        onEvent(CanvasEvent(kind: kind, handler: name, value: value, targetID: targetID))
    }
}

@MainActor
public struct CanvasComponentView: View {
    public let tree: CanvasComponent
    public let focusID: FocusState<String?>.Binding
    /// The session-owned edit buffer for text-field drafts. Drafts only exist while a field is
    /// being edited; after a dispatch re-render the tree's `props.value` is authoritative and
    /// `CanvasSessionView` drops drafts for fields that are no longer the focus target.
    public let fieldDrafts: Binding<[String: String]>
    public let onEvent: (CanvasEvent) -> Void
    public let onEffect: (CanvasEffect) -> Void
    public let onExitContent: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue

    public init(
        tree: CanvasComponent,
        focusID: FocusState<String?>.Binding,
        fieldDrafts: Binding<[String: String]>,
        onEvent: @escaping (CanvasEvent) -> Void,
        onEffect: @escaping (CanvasEffect) -> Void,
        onExitContent: @escaping () -> Void
    ) {
        self.tree = tree
        self.focusID = focusID
        self.fieldDrafts = fieldDrafts
        self.onEvent = onEvent
        self.onEffect = onEffect
        self.onExitContent = onExitContent
    }

    private var effectiveTheme: String {
        let category = PopupThemeModel.category(fromStored: selectedTheme)
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    public var body: some View {
        CanvasTree(node: tree, theme: effectiveTheme, focusID: focusID, fieldDrafts: fieldDrafts,
                   onEvent: onEvent, onEffect: onEffect, onExitContent: onExitContent)
    }
}

// MARK: - Recursive Tree Renderer

/// Renders one canvas node. A concrete struct (not an opaque function) so recursive child rendering
/// through `CanvasTree(node: child, ...)` never defines an opaque return type in terms of itself.
@MainActor
private struct CanvasTree: View {
    let node: CanvasComponent
    let theme: String
    let focusID: FocusState<String?>.Binding
    let fieldDrafts: Binding<[String: String]>
    let onEvent: (CanvasEvent) -> Void
    let onEffect: (CanvasEffect) -> Void
    let onExitContent: () -> Void

    var body: some View {
        content
            .applyNodeID(nodeID)
    }

    private var nodeID: String? {
        switch node {
        case .stack(let props, _): return props.id
        case .divider(let props): return props.id
        case .spacer(let props): return props.id
        case .text(let props): return props.id
        case .icon(let props): return props.id
        case .image(let props): return props.id
        case .button(let props): return props.id
        case .list(let props, _): return props.id
        case .textField(let props): return props.id
        case .toggle(let props): return props.id
        case .link(let props): return props.id
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node {
        case .stack(let props, let children):
            if props.orientation == .horizontal {
                HStack(spacing: props.spacing ?? 8) {
                    ForEach(children.indices, id: \.self) { index in
                        child(children[index])
                    }
                }
            } else {
                VStack(spacing: props.spacing ?? 8) {
                    ForEach(children.indices, id: \.self) { index in
                        child(children[index])
                    }
                }
            }
        case .divider:
            Rectangle()
                .fill(PopupThemeModel.dividerColor(for: theme))
                .frame(height: 1)
        case .spacer(let props):
            Spacer(minLength: props.minLength.map { CGFloat($0) } ?? 0)
        case .text(let props):
            Text(props.content)
                .font(textFont(for: props.style))
                .foregroundColor(textColor(for: props.color))
                .canvasTextSelection(props.selectable)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(2)
        case .icon(let props):
            CanvasIconView(source: props.source, size: props.size)
                .font(.system(size: props.size))
        case .image(let props):
            canvasImage(props)
                .clipShape(RoundedRectangle(cornerRadius: props.cornerRadius ?? 0, style: .continuous))
        case .button(let props):
            CanvasButtonView(props: props, theme: theme, focusID: focusID,
                             onEvent: onEvent, onEffect: onEffect, onExitContent: onExitContent)
        case .list(_, let sections):
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 2) {
                    if let header = section.header {
                        Text(header)
                            .font(.caption)
                            .foregroundStyle(PopupThemeModel.restSecondary(for: theme))
                        Rectangle()
                            .fill(PopupThemeModel.dividerColor(for: theme))
                            .frame(height: 1)
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        listRowView(item)
                    }
                }
            }
        case .textField(let props):
            CanvasTextFieldView(
                props: props,
                text: Binding(
                    get: { fieldDrafts.wrappedValue[props.id] ?? props.value },
                    set: { fieldDrafts.wrappedValue[props.id] = $0 }
                ),
                focusID: focusID,
                onEvent: onEvent,
                onEffect: onEffect,
                onExitContent: onExitContent
            )
        case .toggle(let props):
            CanvasToggleView(props: props, focusID: focusID, onEvent: onEvent, onEffect: onEffect, onExitContent: onExitContent)
        case .link(let props):
            CanvasLinkView(props: props, focusID: focusID, onEffect: onEffect, onExitContent: onExitContent)
        }
    }

    private func child(_ node: CanvasComponent) -> some View {
        CanvasTree(node: node, theme: theme, focusID: focusID, fieldDrafts: fieldDrafts,
                   onEvent: onEvent, onEffect: onEffect, onExitContent: onExitContent)
    }

    private func textFont(for style: CanvasTextStyle) -> Font {
        switch style {
        case .title: return .system(size: 13, weight: .semibold)
        case .body: return .system(size: 13)
        case .caption: return .system(size: 11)
        case .monospaced: return .system(size: 12, design: .monospaced)
        }
    }

    private func textColor(for token: CanvasColorToken) -> Color {
        switch token {
        case .primary: return .primary
        case .secondary: return .secondary
        case .accent: return .accentColor
        }
    }

    // MARK: - Image

    /// Renders a `.image` node: fixed `frame(width:height:)` when the producer supplied a size,
    /// otherwise the column width (`maxWidth: .infinity`); local paths outside the extension
    /// directory are rejected via `Constants.isPathSafe` and render the error placeholder.
    @ViewBuilder
    private func canvasImage(_ props: CanvasImageProps) -> some View {
        imageSource(props.source)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func imageSource(_ source: CanvasImageSource) -> some View {
        switch source {
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: phase.error != nil ? "exclamationmark.triangle" : "circle.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        case .local(let url):
            if Constants.isPathSafe(destinationURL: url, baseDirectory: Constants.extensionsDirectory),
               let nsImage = LocalIconCache.shared.image(for: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }

    // MARK: - List Rows

    @ViewBuilder
    private func listRowView(_ item: CanvasListItem) -> some View {
        let row = HStack(spacing: 8) {
            if let icon = item.icon {
                CanvasIconView(source: icon, size: 16)
                    .foregroundColor(.accentColor)
                    .frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge = item.badge {
                Text(badge)
                    .font(.caption)
                    .foregroundColor(PopupThemeModel.restSecondary(for: theme))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .opacity(item.disabled ? 0.5 : 1)
        .accessibilityLabel(item.subtitle.map { "\(item.title): \($0)" } ?? item.title)

        if let handler = item.handler, !item.disabled {
            Button {
                routeCanvasHandler(handler, kind: .tap, value: nil, targetID: item.id,
                                   onEvent: onEvent, onEffect: onEffect)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .applyFocusID(item.id, focusID)
        } else {
            row
        }
    }
}

// MARK: - Icon

/// Resolves a `CanvasIconSource` through the app's existing icon pipeline: SF Symbol, Iconify
/// "prefix:name" via `IconifySVGView`, a local file via `LocalIconCache` (confined to the extension
/// directory), or a remote URL via `AsyncImage` — `circle.dashed` while loading and
/// `exclamationmark.triangle` on error or when a local path is outside the extension directory.
@MainActor
private struct CanvasIconView: View {
    let source: CanvasIconSource
    let size: CGFloat

    var body: some View {
        switch source {
        case .symbol(let name):
            if name.contains(":") {
                IconifySVGView(iconId: name)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: name.isEmpty ? "star" : name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        case .iconify(let name):
            IconifySVGView(iconId: name)
                .frame(width: size, height: size)
        case .local(let url):
            if Constants.isPathSafe(destinationURL: url, baseDirectory: Constants.extensionsDirectory),
               let nsImage = LocalIconCache.shared.image(for: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: phase.error != nil ? "exclamationmark.triangle" : "circle.dashed")
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Button

@MainActor
private struct CanvasButtonView: View {
    let props: CanvasButtonProps
    let theme: String
    let focusID: FocusState<String?>.Binding
    let onEvent: (CanvasEvent) -> Void
    let onEffect: (CanvasEffect) -> Void
    let onExitContent: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = props.icon {
                    CanvasIconView(source: icon, size: 14)
                }
                Text(props.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(foregroundColor)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(props.disabled)
        .opacity(props.disabled ? 0.5 : 1)
        .applyFocusID(props.id, focusID)
        .onKeyPress(.escape) { onExitContent(); return .handled }
        .accessibilityLabel(props.title)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        if props.style == .accent { return .white }
        return isHovered ? .white : PopupThemeModel.restForeground(for: theme)
    }

    private var backgroundColor: Color {
        if props.style == .accent {
            return isHovered ? Color.accentColor.opacity(0.85) : Color.accentColor
        }
        return isHovered ? Color.accentColor : Color.clear
    }

    private func action() {
        guard !props.disabled, let handler = props.handler else { return }
        routeCanvasHandler(handler, kind: .tap, value: nil, targetID: props.id,
                           onEvent: onEvent, onEffect: onEffect)
    }
}

// MARK: - Text Field

@MainActor
private struct CanvasTextFieldView: View {
    let props: CanvasTextFieldProps
    /// Bound to the session's edit buffer: reads `fieldDrafts[id] ?? props.value`, writes
    /// `fieldDrafts[id]` — an edit buffer, not a value store. The blur commit happens in
    /// `CanvasSessionView`'s `.onChange(of: focusID)` handler.
    let text: Binding<String>
    let focusID: FocusState<String?>.Binding
    let onEvent: (CanvasEvent) -> Void
    let onEffect: (CanvasEffect) -> Void
    let onExitContent: () -> Void

    var body: some View {
        TextField(props.placeholder ?? "", text: text)
            .textFieldStyle(.plain)
            .focusable()
            .focused(focusID, equals: props.id)
            .onSubmit { submit() }
            .onKeyPress(.escape) { onExitContent(); return .handled }
            .accessibilityLabel(props.placeholder?.isEmpty == false ? props.placeholder! : "Text field \(props.id)")
    }

    private func submit() {
        guard let handler = props.onSubmit else { return }
        routeCanvasHandler(handler, kind: .submit, value: text.wrappedValue, targetID: props.id,
                           onEvent: onEvent, onEffect: onEffect)
    }
}

// MARK: - Toggle

@MainActor
private struct CanvasToggleView: View {
    let props: CanvasToggleProps
    let focusID: FocusState<String?>.Binding
    let onEvent: (CanvasEvent) -> Void
    let onEffect: (CanvasEffect) -> Void
    let onExitContent: () -> Void
    /// Local state seeded from the tree's authoritative value for immediate tap feedback; resynced
    /// from `props.value` on every dispatch re-render so an external control flipping the toggle
    /// (e.g. a "select all" button) never leaves it stale.
    @State private var isOn: Bool

    init(props: CanvasToggleProps, focusID: FocusState<String?>.Binding,
         onEvent: @escaping (CanvasEvent) -> Void, onEffect: @escaping (CanvasEffect) -> Void,
         onExitContent: @escaping () -> Void) {
        self.props = props
        self.focusID = focusID
        self.onEvent = onEvent
        self.onEffect = onEffect
        self.onExitContent = onExitContent
        _isOn = State(initialValue: props.value)
    }

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { flipped in
            isOn = flipped
            if let handler = props.onToggle {
                routeCanvasHandler(handler, kind: .change, value: "\(flipped)", targetID: props.id,
                                   onEvent: onEvent, onEffect: onEffect)
            }
        }))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(props.disabled)
        .opacity(props.disabled ? 0.5 : 1)
        .applyFocusID(props.id, focusID)
        .onKeyPress(.escape) { onExitContent(); return .handled }
        .accessibilityLabel("Toggle")
        .onChange(of: props.value) { _, newValue in
            isOn = newValue
        }
        .task(id: props) {
            isOn = props.value
        }
    }
}

// MARK: - Link

@MainActor
private struct CanvasLinkView: View {
    let props: CanvasLinkProps
    let focusID: FocusState<String?>.Binding
    let onEffect: (CanvasEffect) -> Void
    let onExitContent: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onEffect(.openURL(props.url))
        } label: {
            Text(props.title)
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .applyFocusID(props.id, focusID)
        .onKeyPress(.escape) { onExitContent(); return .handled }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(props.title)
    }
}

// MARK: - Conditional Modifiers

private extension View {
    /// Applies `.id(id)` only when the node carries one — `nil` means "no identity, full
    /// replacement" so sibling nodes without ids never collide on a shared `nil` identity.
    @ViewBuilder
    func applyNodeID(_ id: String?) -> some View {
        if let id {
            self.id(id)
        } else {
            self
        }
    }

    /// `.focusable()` + `.focused($focusID, equals:)` for interactive nodes when they carry an id.
    @ViewBuilder
    func applyFocusID(_ id: String?, _ focusID: FocusState<String?>.Binding) -> some View {
        if let id {
            self.focusable().focusEffectDisabled().focused(focusID, equals: id)
        } else {
            self
        }
    }

    /// `.textSelection(.enabled)` only for selectable text nodes.
    @ViewBuilder
    func canvasTextSelection(_ enabled: Bool) -> some View {
        if enabled {
            self.textSelection(.enabled)
        } else {
            self
        }
    }
}
