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
    private static let gap: CGFloat = 6

    /// Main entry point — positions relative to mouse release point, drag direction, alignment, and vertical placement mode.
    public static func calculateFrame(
        for context: SelectionContext,
        popupSize: CGSize,
        in screenBounds: CGRect,
        alignment: PopupBarAlignment = .left,
        verticalPosition: PopupVerticalPosition = .auto
    ) -> CGRect {
        placeNearReleasePoint(
            releasePoint: context.cursorPosition,
            mouseDownPoint: context.mouseDownLocation,
            popupSize: popupSize,
            screenBounds: screenBounds,
            alignment: alignment,
            verticalPosition: verticalPosition
        )
    }

    /// Distance from the window frame's left edge to the center of the first action button
    /// (shadow inset + half the button width).
    public static let firstActionCenterOffset: CGFloat = PopupMetrics.popupShadowInset + (PopupMetrics.actionButtonWidth / 2)

    /// Returns true if the placed popup frame sits above the cursor release point.
    public static func isPlacedAbove(frame: CGRect, releasePoint: CGPoint) -> Bool {
        frame.minY >= releasePoint.y
    }

    /// Horizontal origin that aligns a popup of the given width relative to the release X,
    /// clamped to the screen's padding-inset edges.
    public static func alignedX(
        releaseX: CGFloat,
        width: CGFloat,
        screenBounds: CGRect,
        alignment: PopupBarAlignment = .left
    ) -> CGFloat {
        let padding: CGFloat = PopupMetrics.popupPadding

        // --- Clamp popup width so a too-wide popup never overflows the right edge ---
        let maxPopupWidth = max(0, screenBounds.width - 2 * padding)
        let popupWidth = max(0, min(width, maxPopupWidth))

        let unconstrainedX: CGFloat
        switch alignment {
        case .left:
            unconstrainedX = releaseX - firstActionCenterOffset
        case .center:
            unconstrainedX = releaseX - popupWidth / 2
        case .right:
            unconstrainedX = releaseX - (popupWidth - firstActionCenterOffset)
        }

        let minX = screenBounds.minX + padding
        let maxX = screenBounds.maxX - popupWidth - padding
        if maxX >= minX {
            return max(minX, min(unconstrainedX, maxX))
        } else {
            return minX
        }
    }

    /// Horizontal origin that centers a popup of the given width on the release X, clamped to the
    /// screen's padding-inset edges. Used for both initial placement and re-centering on resize so a
    /// width change (search palette, pagination) never drifts the bar off the cursor.
    public static func centeredX(releaseX: CGFloat, width: CGFloat, screenBounds: CGRect) -> CGFloat {
        alignedX(releaseX: releaseX, width: width, screenBounds: screenBounds, alignment: .center)
    }

    /// Place the popup near the mouse-release point.
    ///
    /// Vertical rule:
    ///  - Auto:
    ///     * Top-to-Bottom drag (mouse released below start point): place BELOW cursor so it doesn't cover selected text.
    ///     * Bottom-to-Top or Horizontal drag: place ABOVE cursor.
    ///     * Flips if near screen edge.
    ///  - Above: place ABOVE cursor by default; flips to below if near screen top edge.
    ///  - Below: place BELOW cursor by default; flips to above if near screen bottom edge.
    public static func placeNearReleasePoint(
        releasePoint: CGPoint,
        mouseDownPoint: CGPoint? = nil,
        popupSize: CGSize,
        screenBounds: CGRect,
        alignment: PopupBarAlignment = .left,
        verticalPosition: PopupVerticalPosition = .auto
    ) -> CGRect {
        let padding: CGFloat = PopupMetrics.popupPadding

        // --- Clamp popup width so a too-wide popup never overflows the right edge ---
        let maxPopupWidth = max(0, screenBounds.width - 2 * padding)
        let popupWidth = max(0, min(popupSize.width, maxPopupWidth))

        // --- Horizontal: align relative to release X, clamp to edges ---
        let x = alignedX(releaseX: releasePoint.x, width: popupWidth, screenBounds: screenBounds, alignment: alignment)

        // --- Vertical Direction Check ---
        // macOS screen coords: Y increases upwards (0 is bottom of screen).
        // Top-to-Bottom drag -> releasePoint.y < mouseDownPoint.y.
        let isDraggingDown: Bool = {
            guard let mouseDown = mouseDownPoint else { return false }
            return (releasePoint.y - mouseDown.y) < -10.0
        }()

        let shouldPlaceBelow: Bool
        switch verticalPosition {
        case .auto:
            shouldPlaceBelow = isDraggingDown
        case .above:
            shouldPlaceBelow = false
        case .below:
            shouldPlaceBelow = true
        }

        let yAbove = releasePoint.y + gap
        let yBelow = releasePoint.y - popupSize.height - gap

        var y: CGFloat
        if shouldPlaceBelow {
            // Dragged down or forced below -> place BELOW cursor by default
            if yBelow >= screenBounds.minY + padding {
                y = yBelow
            } else if yAbove + popupSize.height <= screenBounds.maxY - padding {
                y = yAbove
            } else {
                y = screenBounds.minY + padding
            }
        } else {
            // Dragged up/horizontal or forced above -> place ABOVE cursor by default
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

    /// Selects the screen containing `point`, with a 2pt inclusive margin so cursor coordinates
    /// resting exactly on the maxX/maxY boundaries of secondary displays do not fail resolution.
    public static func screen(containing point: CGPoint, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) } ?? screens.first
    }

    /// Selects the screen frame containing `point` with inclusive boundary tolerance.
    public static func screenFrame(containing point: CGPoint, screenFrames: [CGRect]) -> CGRect? {
        screenFrames.first { $0.insetBy(dx: -2, dy: -2).contains(point) } ?? screenFrames.first
    }
}
