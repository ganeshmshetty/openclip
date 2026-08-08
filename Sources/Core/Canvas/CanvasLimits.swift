// CanvasLimits.swift
// OpenClip
//
// Core constants bounding a canvas tree (spec §5.3) so a buggy or hostile extension cannot emit a
// pathological tree, plus the shared structural validator used by both CanvasElementParser (Task 6)
// and native mounts (CanvasSessionController). A violation rejects the whole canvas with an error
// status — it is never truncated or partially rendered. Pure Core — no AppKit/SwiftUI.
import Foundation
import CoreGraphics

public enum CanvasLimits {
    /// Max nodes in a canvas tree (spec §5.3).
    public static let maxNodes = 512
    /// Max nesting depth: each nested `stack` or `list` adds one level (spec §5.3).
    public static let maxDepth = 32
    /// Max list items per `list` node (spec §5.3, confirmed 2026-08-08).
    public static let maxListItems = 64
    /// Max characters per `text` node (spec §5.3, confirmed 2026-08-08: 32k because a typical AI
    /// completion runs 15–18k chars).
    public static let maxTextLength = 32_000
    /// Canvas body width constraints (spec §7.1); clamped to screen minus popup padding at render.
    public static let canvasMinWidth: CGFloat = 220
    public static let canvasIdealWidth: CGFloat = 300
    public static let canvasMaxWidth: CGFloat = 360
}

/// Structural validation failure. These reject the whole canvas (spec §5.3, §11).
public enum CanvasParseError: Error, Equatable {
    case tooManyNodes
    case depthExceeded
    case tooManyListItems
    case textTooLong
    case nonObjectRoot
}

public enum CanvasTreeValidator {
    /// Validates the whole tree against CanvasLimits. Throws CanvasParseError on the first violation.
    public static func validate(_ tree: CanvasComponent) throws {
        var nodeCount = 0
        func walk(_ node: CanvasComponent, depth: Int) throws {
            nodeCount += 1
            if nodeCount > CanvasLimits.maxNodes { throw CanvasParseError.tooManyNodes }
            if depth > CanvasLimits.maxDepth { throw CanvasParseError.depthExceeded }
            switch node {
            case .stack(_, let children):
                for child in children {
                    try walk(child, depth: depth + 1)
                }
            case .text(let props):
                if props.content.count > CanvasLimits.maxTextLength { throw CanvasParseError.textTooLong }
            case .list(_, let sections):
                let itemCount = sections.reduce(0) { $0 + $1.items.count }
                if itemCount > CanvasLimits.maxListItems { throw CanvasParseError.tooManyListItems }
            case .divider(_), .spacer(_), .icon(_), .image(_), .button(_), .textField(_), .toggle(_), .link(_):
                break
            }
        }
        try walk(tree, depth: 0)
    }
}
