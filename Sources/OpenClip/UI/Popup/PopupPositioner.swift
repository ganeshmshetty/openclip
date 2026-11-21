// PopupPositioner.swift
// OpenClip
//
// Calculates popup window placement and screen edge clamping math based on selection bounds or cursor location.
import Foundation
import CoreGraphics
import Core
import AppKit

enum PopupDismissalGrace {
    static func isActive(now: TimeInterval, deadline: TimeInterval?) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }
}

public struct PopupPositioner: Sendable {

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

    /// Horizontal origin centering a popup on the release X. Used for initial placement and for re-centering on resize,
    /// so a width change never drifts the bar off the cursor.
    public static func centeredX(releaseX: CGFloat, width: CGFloat, screenBounds: CGRect) -> CGFloat {
        alignedX(releaseX: releaseX, width: width, screenBounds: screenBounds, alignment: .center)
    }


    /// Horizontal midX for a search palette: aligns with the button center, capped so its right edge stays
    /// within `barMaxX`, and clamped to the screen.
    public static func searchPaletteMidX(
        buttonScreenMidX: CGFloat,
        searchWidth: CGFloat = PopupMetrics.searchPanelWidth,
        barMaxX: CGFloat,
        screenBounds: CGRect
    ) -> CGFloat {
        let padding = PopupMetrics.popupPadding
        let minMidX = screenBounds.minX + padding + searchWidth / 2
        let maxMidX = max(minMidX, screenBounds.maxX - padding - searchWidth / 2)
        let barMaxMidX = barMaxX - searchWidth / 2
        let targetMidX = min(buttonScreenMidX, barMaxMidX)
        return max(minMidX, min(targetMidX, maxMidX))
    }

    /// Places the popup near the release point. Auto puts it below when the drag went top-to-bottom (so it does not
    /// cover the selection), otherwise above. Each side flips at a screen edge; `.above`/`.below` force the side.
    public static func placeNearReleasePoint(
        releasePoint: CGPoint,
        mouseDownPoint: CGPoint? = nil,
        popupSize: CGSize,
        screenBounds: CGRect,
        alignment: PopupBarAlignment = .left,
        verticalPosition: PopupVerticalPosition = .auto
    ) -> CGRect {
        let padding: CGFloat = PopupMetrics.popupPadding

        let maxPopupWidth = max(0, screenBounds.width - 2 * padding)
        let popupWidth = max(0, min(popupSize.width, maxPopupWidth))

        let x = alignedX(releaseX: releasePoint.x, width: popupWidth, screenBounds: screenBounds, alignment: alignment)

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
            if yBelow >= screenBounds.minY + padding {
                y = yBelow
            } else if yAbove + popupSize.height <= screenBounds.maxY - padding {
                y = yAbove
            } else {
                y = screenBounds.minY + padding
            }
        } else {
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

    /// Screen containing `point`, with a 2pt boundary tolerance so points on secondary-display edges still resolve.
    public static func screen(containing point: CGPoint, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
    }

    /// Selects the screen frame containing `point` with inclusive boundary tolerance.
    public static func screenFrame(containing point: CGPoint, screenFrames: [CGRect]) -> CGRect? {
        screenFrames.first { $0.insetBy(dx: -2, dy: -2).contains(point) } ?? screenFrames.first
    }
}
