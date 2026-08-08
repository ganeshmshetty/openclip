// CanvasFocus.swift
// OpenClip
//
// Pure Core helper resolving the component that should receive initial focus when a canvas mounts
// (spec §7, focusFirstInteractive): a TWO-PASS depth-first (pre-order) walk. Pass 1 returns the
// first `textField` anywhere in the tree — a button that appears earlier never beats a field. Pass
// 2 (only when no textField exists) returns the first non-disabled interactive node among
// `button`/`toggle`/`listItem`/`link` carrying a node id; else nil — in which case the caller
// focuses the canvas root (always .focusable()). textField/toggle ids are required (state key +
// focus id); button/link/listItem need a non-nil id to be a focus target. Divider/spacer/text/icon/
// image are never focus targets; only `.stack` nodes recurse into children.
import Foundation

public extension CanvasComponent {
    /// Pre-order child components of a structural node; leaves (and `.list`) have none.
    private var subnodes: [CanvasComponent] {
        switch self {
        case .stack(_, let children): return children
        default: return []
        }
    }

    func firstInteractiveID() -> String? {
        // Pass 1 (spec step 1): the first textField anywhere in the tree.
        var stack: [CanvasComponent] = [self]
        while let node = stack.popLast() {
            if case .textField(let props) = node { return props.id }
            stack.append(contentsOf: node.subnodes.reversed())
        }

        // Pass 2 (spec step 2): the first non-disabled button/toggle/listItem/link with a node id.
        stack = [self]
        while let node = stack.popLast() {
            switch node {
            case .button(let props):
                if !props.disabled, let id = props.id { return id }
            case .toggle(let props):
                return props.id
            case .list(_, let sections):
                for section in sections.reversed() {
                    for item in section.items.reversed() {
                        if !item.disabled, let id = item.id { return id }
                    }
                }
            case .link(let props):
                if let id = props.id { return id }
            default:
                break
            }
            stack.append(contentsOf: node.subnodes.reversed())
        }
        return nil
    }
}
