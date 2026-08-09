// CanvasDSL.swift
// OpenClip
//
// Value DSL over the same component tree (spec §6): handlers are values, not closures, so the tree
// stays Equatable + Sendable. `Canvas.build { ... }` wraps the result-builder content in a vertical
// stack. Constructors are namespaced on `Canvas` (Canvas.text(...), Canvas.button(...), ...) to
// avoid clashing with SwiftUI's Text/Button in App-target callers. Native actions needing named
// interactive handlers register them with CanvasSessionController (deferred in v1 — most native
// interactivity is .effect). Pure Core — no AppKit/SwiftUI.
import Foundation

@resultBuilder
public enum CanvasBuilder {
    public static func buildBlock(_ components: [CanvasComponent]...) -> [CanvasComponent] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: CanvasComponent) -> [CanvasComponent] {
        [expression]
    }

    public static func buildExpression(_ expression: [CanvasComponent]) -> [CanvasComponent] {
        expression
    }

    public static func buildOptional(_ component: [CanvasComponent]?) -> [CanvasComponent] {
        component ?? []
    }

    public static func buildEither(first component: [CanvasComponent]) -> [CanvasComponent] {
        component
    }

    public static func buildEither(second component: [CanvasComponent]) -> [CanvasComponent] {
        component
    }

    public static func buildArray(_ components: [[CanvasComponent]]) -> [CanvasComponent] {
        components.flatMap { $0 }
    }
}

public enum Canvas {
    /// Wraps the builder content in a vertical stack — the root of a native canvas tree.
    public static func build(@CanvasBuilder _ content: () -> [CanvasComponent]) -> CanvasComponent {
        .stack(CanvasStackProps(), content())
    }

    public static var divider: CanvasComponent { .divider(CanvasDividerProps()) }

    public static func spacer(minLength: Double? = nil, id: String? = nil) -> CanvasComponent {
        .spacer(CanvasSpacerProps(id: id, minLength: minLength))
    }

    public static func text(_ content: String, id: String? = nil, style: CanvasTextStyle = .body,
                            color: CanvasColorToken = .primary, selectable: Bool = false) -> CanvasComponent {
        .text(CanvasTextProps(id: id, content: content, style: style, color: color, selectable: selectable))
    }

    public static func icon(_ source: CanvasIconSource, size: Double = 14, id: String? = nil) -> CanvasComponent {
        .icon(CanvasIconProps(id: id, source: source, size: size))
    }

    public static func image(_ source: CanvasImageSource, cornerRadius: Double? = nil, id: String? = nil) -> CanvasComponent {
        .image(CanvasImageProps(id: id, source: source, cornerRadius: cornerRadius))
    }

    public static func button(_ title: String, id: String? = nil, icon: CanvasIconSource? = nil,
                              style: CanvasButtonStyle = .plain, disabled: Bool = false,
                              handler: CanvasHandler? = nil) -> CanvasComponent {
        .button(CanvasButtonProps(id: id, title: title, icon: icon, style: style, disabled: disabled, handler: handler))
    }

    public static func stack(_ props: CanvasStackProps = CanvasStackProps(),
                             @CanvasBuilder _ content: () -> [CanvasComponent]) -> CanvasComponent {
        .stack(props, content())
    }

    public static func hstack(spacing: Double? = nil, id: String? = nil,
                              @CanvasBuilder _ content: () -> [CanvasComponent]) -> CanvasComponent {
        .stack(CanvasStackProps(id: id, orientation: .horizontal, spacing: spacing), content())
    }

    public static func vstack(spacing: Double? = nil, id: String? = nil,
                              @CanvasBuilder _ content: () -> [CanvasComponent]) -> CanvasComponent {
        .stack(CanvasStackProps(id: id, orientation: .vertical, spacing: spacing), content())
    }

    public static func list(_ sections: [CanvasListSection], id: String? = nil) -> CanvasComponent {
        .list(CanvasListProps(id: id), sections)
    }

    public static func textField(_ id: String, value: String = "", placeholder: String? = nil,
                                 onSubmit: CanvasHandler? = nil, onChange: CanvasHandler? = nil) -> CanvasComponent {
        .textField(CanvasTextFieldProps(id: id, value: value, placeholder: placeholder,
                                        onSubmit: onSubmit, onChange: onChange))
    }

    public static func toggle(_ id: String, value: Bool, disabled: Bool = false, onToggle: CanvasHandler? = nil) -> CanvasComponent {
        .toggle(CanvasToggleProps(id: id, value: value, disabled: disabled, onToggle: onToggle))
    }

    public static func link(_ title: String, url: URL, id: String? = nil) -> CanvasComponent {
        .link(CanvasLinkProps(id: id, title: title, url: url))
    }
}
