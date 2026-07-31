import Foundation
import CoreGraphics
import Core
import AppKit

public struct PopupPositioner: Sendable {

    // How far the popup sits from the release point (points)
    private static let gap: CGFloat = 12

    /// Main entry point — always positions relative to mouse release point.
    /// Ignores selectionBounds entirely (they're unreliable and cause inconsistent placement).
    public static func calculateFrame(
        for context: SelectionContext,
        popupSize: CGSize,
        in screenBounds: CGRect
    ) -> CGRect {
        placeNearReleasePoint(
            releasePoint: context.cursorPosition,
            popupSize: popupSize,
            screenBounds: screenBounds
        )
    }

    /// Place the popup near the mouse-release point.
    ///
    /// Vertical rule:
    ///  - Default: appear ABOVE the release point (gap px above cursor).
    ///  - If not enough room above: appear BELOW instead.
    ///
    /// Horizontal rule:
    ///  - Center on the release point X.
    ///  - Clamp to screen edges with padding.
    ///
    /// This means the popup always appears near where the user let go of the mouse,
    /// regardless of whether they dragged top→bottom or bottom→top.
    public static func placeNearReleasePoint(
        releasePoint: CGPoint,
        popupSize: CGSize,
        screenBounds: CGRect
    ) -> CGRect {
        let padding: CGFloat = Constants.popupPadding

        // --- Horizontal: center on release X, clamp to edges ---
        var x = releasePoint.x - popupSize.width / 2
        x = max(screenBounds.minX + padding, min(x, screenBounds.maxX - popupSize.width - padding))

        // --- Vertical: above by default, flip below if not enough room ---
        let yAbove = releasePoint.y + gap
        let yBelow = releasePoint.y - popupSize.height - gap

        var y: CGFloat
        if yAbove + popupSize.height <= screenBounds.maxY - padding {
            // Enough room above — place above cursor
            y = yAbove
        } else if yBelow >= screenBounds.minY + padding {
            // Not enough room above — flip below cursor
            y = yBelow
        } else {
            // Last resort: clamp to top of screen
            y = screenBounds.maxY - popupSize.height - padding
        }

        return CGRect(x: x, y: y, width: popupSize.width, height: popupSize.height)
    }
}
