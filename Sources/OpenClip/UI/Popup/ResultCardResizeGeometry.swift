// ResultCardResizeGeometry.swift
// OpenClip
//
// Pure geometry for resizing the result card by its right/bottom handles: the card's top-left
// corner stays fixed (the header is the move handle), the dragged edge follows the absolute cursor
// position, and the result is clamped to the card's minimum size and to the screen the panel sits
// on. Free of AppKit state so the rules are unit-testable without a live panel.
import CoreGraphics

public enum ResultCardResizeGeometry {
    /// The card size implied by the cursor having moved from `anchorMouse` (where the drag began,
    /// when the card measured `anchorSize`) to `mouse`, both in screen coordinates (y up). Only
    /// the dimensions the handle controls change: a bottom-edge drag never touches the width.
    public static func size(from anchorSize: CGSize, edge: ResultCardResizeEdge,
                            anchorMouse: CGPoint, mouse: CGPoint) -> CGSize {
        var size = anchorSize
        if edge.resizesWidth {
            size.width = anchorSize.width + (mouse.x - anchorMouse.x)
        }
        if edge.resizesHeight {
            // Screen y grows upward: pulling the bottom edge down makes the card taller.
            size.height = anchorSize.height + (anchorMouse.y - mouse.y)
        }
        return size
    }

    /// Clamps a proposed card size so the card never shrinks below its minimum and the panel
    /// around it (card plus shadow ring) stays inside `screenBounds` by `PopupMetrics.popupPadding`
    /// while growing from a fixed `panelTopLeft`. When the panel already sits too close to a screen
    /// edge for even the minimum card, the minimum wins — the card must stay usable.
    public static func clamp(_ proposed: CGSize, panelTopLeft: CGPoint, screenBounds: CGRect) -> CGSize {
        let ring = 2 * PopupMetrics.popupShadowInset
        let padding = PopupMetrics.popupPadding
        let maxWidth = screenBounds.maxX - padding - panelTopLeft.x - ring
        let maxHeight = panelTopLeft.y - (screenBounds.minY + padding) - ring
        return CGSize(
            width: bounded(proposed.width, min: PopupMetrics.aiCardMinWidth, max: maxWidth),
            height: bounded(proposed.height, min: PopupMetrics.aiCardMinHeight, max: maxHeight)
        )
    }

    /// Fits a remembered size to what `screenBounds` can show at all (panel inside the screen by
    /// `popupPadding` on every side), independent of where the panel will be placed — placement
    /// is decided afterwards and nudged back on-screen by the controller. A size remembered on a
    /// large external display must still open usable on a laptop screen.
    public static func fit(_ remembered: CGSize, in screenBounds: CGRect) -> CGSize {
        let ring = 2 * PopupMetrics.popupShadowInset
        let padding = 2 * PopupMetrics.popupPadding
        return CGSize(
            width: bounded(remembered.width, min: PopupMetrics.aiCardMinWidth, max: screenBounds.width - padding - ring),
            height: bounded(remembered.height, min: PopupMetrics.aiCardMinHeight, max: screenBounds.height - padding - ring)
        )
    }

    /// `value` limited to `min...max`, with the minimum taking precedence when `max` is smaller.
    private static func bounded(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(maximum, minimum))
    }
}
