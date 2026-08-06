// PopupPositioner.swift
// OpenClip
//
// Calculates popup window placement and screen edge clamping math based on selection bounds or cursor location.
import Foundation
import CoreGraphics
import Core
import AppKit

public struct PopupPositioner: Sendable {

    // How far the popup sits from the release point (points)
    private static let gap: CGFloat = 12

    /// Main entry point — positions relative to mouse release point and drag direction.
    public static func calculateFrame(
        for context: SelectionContext,
        popupSize: CGSize,
        in screenBounds: CGRect
    ) -> CGRect {
        placeNearReleasePoint(
            releasePoint: context.cursorPosition,
            mouseDownPoint: context.mouseDownLocation,
            popupSize: popupSize,
            screenBounds: screenBounds
        )
    }

    /// Horizontal origin that centers a popup of the given width on the release X, clamped to the
    /// screen's padding-inset edges. Used for both initial placement and re-centering on resize so a
    /// width change (search palette, pagination) never drifts the bar off the cursor.
    public static func centeredX(releaseX: CGFloat, width: CGFloat, screenBounds: CGRect) -> CGFloat {
        let padding: CGFloat = Constants.popupPadding

        // --- Clamp popup width so a too-wide popup never overflows the right edge ---
        let maxPopupWidth = max(0, screenBounds.width - 2 * padding)
        let popupWidth = max(0, min(width, maxPopupWidth))

        // --- Horizontal: center on release X, clamp to edges ---
        var x = releaseX - popupWidth / 2
        return max(screenBounds.minX + padding, min(x, screenBounds.maxX - popupWidth - padding))
    }

    /// Place the popup near the mouse-release point.
    ///
    /// Vertical rule:
    ///  - Top-to-Bottom drag (mouse released below start point): place BELOW cursor so it doesn't cover selected text.
    ///  - Bottom-to-Top or Horizontal drag: place ABOVE cursor.
    ///  - Flips if near screen edge.
    public static func placeNearReleasePoint(
        releasePoint: CGPoint,
        mouseDownPoint: CGPoint? = nil,
        popupSize: CGSize,
        screenBounds: CGRect
    ) -> CGRect {
        let padding: CGFloat = Constants.popupPadding

        // --- Clamp popup width so a too-wide popup never overflows the right edge ---
        let maxPopupWidth = max(0, screenBounds.width - 2 * padding)
        let popupWidth = max(0, min(popupSize.width, maxPopupWidth))

        // --- Horizontal: center on release X, clamp to edges ---
        let x = centeredX(releaseX: releasePoint.x, width: popupWidth, screenBounds: screenBounds)

        // --- Vertical Direction Check ---
        // macOS screen coords: Y increases upwards (0 is bottom of screen).
        // Top-to-Bottom drag -> releasePoint.y < mouseDownPoint.y.
        // The text sits ABOVE the release point. Placing popup above would cover the text!
        let isDraggingDown: Bool = {
            guard let mouseDown = mouseDownPoint else { return false }
            return (releasePoint.y - mouseDown.y) < -10.0
        }()

        let yAbove = releasePoint.y + gap
        let yBelow = releasePoint.y - popupSize.height - gap

        var y: CGFloat
        if isDraggingDown {
            // Dragged down -> text is above cursor -> place BELOW cursor by default
            if yBelow >= screenBounds.minY + padding {
                y = yBelow
            } else if yAbove + popupSize.height <= screenBounds.maxY - padding {
                y = yAbove
            } else {
                y = screenBounds.minY + padding
            }
        } else {
            // Dragged up or horizontal -> text is below/beside cursor -> place ABOVE cursor by default
            if yAbove + popupSize.height <= screenBounds.maxY - padding {
                y = yAbove
            } else if yBelow >= screenBounds.minY + padding {
                y = yBelow
            } else {
                y = screenBounds.maxY - popupSize.height - padding
            }
        }

        return CGRect(x: x, y: y, width: popupWidth, height: popupSize.height)
    }
}
