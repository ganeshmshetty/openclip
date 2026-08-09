// CanvasElementParser.swift
// OpenClip
//
// Parses a CanvasElementSpec tree into a CanvasComponent (spec §5.4). Recovery is lenient per node
// and strict structurally: unknown element types drop the node, malformed/unknown handlers render
// the node non-interactive, invalid link URLs drop the node, missing textField/toggle ids drop the
// node, non-array children are ignored, and unknown color/style tokens fall back to the default —
// a malformed element never crashes the session. Only structural violations (limits, a non-object
// root) throw CanvasParseError and reject the whole canvas.
import Foundation

public enum CanvasElementParser {
    /// Parses a whole element tree, validating structural limits via CanvasTreeValidator.
    public static func parseTree(_ spec: CanvasElementSpec) throws -> CanvasComponent {
        guard let node = parseElement(spec, depth: 0) else {
            throw CanvasParseError.nonObjectRoot
        }
        try CanvasTreeValidator.validate(node)
        return node
    }

    /// Parses one element leniently. Returns nil to drop the node (spec §5.4 recovery).
    static func parseElement(_ spec: CanvasElementSpec, depth: Int = 0) -> CanvasComponent? {
        guard depth <= CanvasLimits.maxDepth else { return nil }
        let props = spec.props
        switch spec.type {
        case "stack":
            var children: [CanvasComponent] = []
            for childSpec in spec.children {
                if let node = parseElement(childSpec, depth: depth + 1) { children.append(node) }
            }
            let orientation: CanvasOrientation =
                props.string("orientation") == "horizontal" ? .horizontal : .vertical
            let spacing = props.double("spacing")
            return .stack(CanvasStackProps(id: props.string("id"), orientation: orientation, spacing: spacing), children)

        case "divider":
            return .divider(CanvasDividerProps(id: props.string("id")))

        case "spacer":
            return .spacer(CanvasSpacerProps(id: props.string("id"), minLength: props.double("minLength")))

        case "text":
            let content = props.string("content") ?? ""
            let style = CanvasTextStyle(rawValue: props.string("style") ?? "body") ?? .body
            let color = CanvasColorToken(rawValue: props.string("color") ?? "primary") ?? .primary
            return .text(CanvasTextProps(
                id: props.string("id"),
                content: content,
                style: style,
                color: color,
                selectable: props.bool("selectable") ?? false
            ))

        case "icon":
            guard let source = parseIconSource(props) else { return nil }
            return .icon(CanvasIconProps(id: props.string("id"), source: source, size: props.double("size") ?? 14))

        case "image":
            guard let source = parseImageSource(props) else { return nil }
            // Size (`{ width, height }` object, spec §7.1) is left nil here; the renderer
            // (`03-session-renderer.md`, Task 12) bounds oversized images to the column.
            return .image(CanvasImageProps(
                id: props.string("id"),
                source: source,
                cornerRadius: props.double("cornerRadius")
            ))

        case "button":
            let handler = parseHandler(in: props, key: "handler")
            let style: CanvasButtonStyle =
                props.string("style") == "accent" ? .accent : .plain
            return .button(CanvasButtonProps(
                id: props.string("id"),
                title: props.string("title") ?? "",
                icon: parseIconSource(props),
                style: style,
                disabled: props.bool("disabled") ?? false,
                handler: handler
            ))

        case "list":
            var items: [CanvasListItem] = []
            for childSpec in spec.children {
                guard childSpec.type == "listItem" else { continue }
                items.append(parseListItem(childSpec))
            }
            // v1 JS: the list's collected listItems are wrapped in a single implicit
            // `CanvasListSection` — section headers are not yet exposed in the `h()` contract
            // (spec §7 list sections land with the renderer in `03-session-renderer.md`, Task 12).
            return .list(CanvasListProps(id: props.string("id")), [CanvasListSection(items: items)])

        case "textField":
            guard let id = props.string("id") else { return nil }
            return .textField(CanvasTextFieldProps(
                id: id,
                value: props.string("value") ?? "",
                placeholder: props.string("placeholder"),
                onSubmit: parseHandler(in: props, key: "onSubmit"),
                onChange: parseHandler(in: props, key: "onChange")
            ))

        case "toggle":
            guard let id = props.string("id") else { return nil }
            return .toggle(CanvasToggleProps(
                id: id,
                value: props.bool("value") ?? false,
                disabled: props.bool("disabled") ?? false,
                onToggle: parseHandler(in: props, key: "onToggle")
            ))

        case "link":
            guard let title = props.string("title"),
                  let urlString = props.string("url"),
                  let url = URL(string: urlString) else { return nil }
            return .link(CanvasLinkProps(id: props.string("id"), title: title, url: url))

        default:
            return nil // unknown element type — drop the node, keep siblings
        }
    }

    private static func parseListItem(_ spec: CanvasElementSpec) -> CanvasListItem {
        let props = spec.props
        return CanvasListItem(
            id: props.string("id"),
            icon: parseIconSource(props),
            title: props.string("title") ?? "",
            subtitle: props.string("subtitle"),
            badge: props.string("badge"),
            disabled: props.bool("disabled") ?? false,
            handler: parseHandler(in: props, key: "handler")
        )
    }

    /// A handler is either a bare `handler` string (dispatch) or an effect object (H2).
    /// `props` holds the node's props; `handlerKey` is `"handler"` for buttons/listItems,
    /// `"onSubmit"`/`"onChange"`/`"onToggle"` for fields/toggles.
    private static func parseHandler(in props: [String: JSONValue], key handlerKey: String) -> CanvasHandler? {
        if case .string(let name) = props[handlerKey], !name.isEmpty {
            return .dispatch(name)
        }
        if case .object(let dict) = props[handlerKey], let effect = parseEffect(dict) {
            return .effect(effect)
        }
        return nil
    }

    /// Parses a `{ type: "…", ... }` effect object (spec §3 `CanvasHandler.effect`).
    /// `type` is one of the 9 leaf effect names; parsing failure → nil → the node stays static.
    private static func parseEffect(_ dict: [String: JSONValue]) -> CanvasEffect? {
        guard let type = dict.string("type") else { return nil }
        switch type {
        case "paste":         return dict.string("text").map(CanvasEffect.paste)
        case "copy":          return dict.string("text").map(CanvasEffect.copy)
        case "cut":           return dict.string("text").map(CanvasEffect.cut)
        case "simulatePaste": return .simulatePaste
        case "keyPress":
            guard let key = dict.string("key") else { return nil }
            return .keyPress(KeyPressSpec(key: key))
        case "runShortcut":
            guard let name = dict.string("name") else { return nil }
            return .runShortcut(name: name, input: dict.string("input"))
        case "openURL":
            guard let urlString = dict.string("url"), let url = URL(string: urlString) else { return nil }
            return .openURL(url)
        case "showServices":  return dict.string("text").map(CanvasEffect.showServices)
        case "notify":
            guard let title = dict.string("title") else { return nil }
            return .notify(title: title, body: dict.string("body") ?? "")
        default: return nil
        }
    }

    private static func parseIconSource(_ props: [String: JSONValue]) -> CanvasIconSource? {
        if let symbol = props.string("symbol") { return .symbol(symbol) }
        if let iconify = props.string("iconify") { return .iconify(iconify) }
        if let local = props.string("local"), let url = URL(string: local) { return .local(url) }
        if let urlString = props.string("url"), let url = URL(string: urlString) { return .url(url) }
        return nil
    }

    private static func parseImageSource(_ props: [String: JSONValue]) -> CanvasImageSource? {
        if let urlString = props.string("url"), let url = URL(string: urlString) { return .url(url) }
        if let local = props.string("local"), let url = URL(string: local) { return .local(url) }
        return nil
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        if case .string(let value) = self[key] { return value }
        return nil
    }
    func bool(_ key: String) -> Bool? {
        if case .bool(let value) = self[key] { return value }
        return nil
    }
    func double(_ key: String) -> Double? {
        if case .number(let value) = self[key] { return value }
        return nil
    }
}
