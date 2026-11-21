import AppKit

/// Rejects mouse-gesture results whose selection is not where the gesture happened.
///
/// AX reports the document's selection, not the gesture's. Chromium's double-click selects the
/// word *closest* to the hit point even over a video, so a player whose controls are faded to
/// `opacity: 0` yields a real but invisible selection far from the click (issue #162). A stale
/// selection elsewhere in the document has the same shape. Missing or unusable bounds fail open.
internal enum SelectionGestureLocality {
    enum Gesture: Equatable, Sendable {
        case multiClick(at: CGPoint)
        case drag(from: CGPoint, to: CGPoint)
    }

    /// Cocoa screen frames plus the primary display's top edge, used to flip AX bounds.
    struct ScreenLayout: Sendable {
        let primaryMaxY: CGFloat
        let frames: [CGRect]

        @MainActor
        static var current: ScreenLayout {
            let screens = NSScreen.screens
            let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
            return ScreenLayout(primaryMaxY: primary?.frame.maxY ?? 0, frames: screens.map(\.frame))
        }
    }

    /// Slack for word-boundary snapping and AX line-box rounding around the pointer.
    static let tolerance: CGFloat = 12
    /// Vertical slack for drags. A press can land in the padding below the first selected line, so
    /// AX's line box sits outside the drag rectangle by roughly a paragraph gap. Kept far below the
    /// distance at which a stale selection elsewhere is rejected.
    static let dragVerticalTolerance: CGFloat = 48
    static let minimumMeaningfulSide: CGFloat = 2

    /// - Parameters:
    ///   - axBounds: selection bounds in AX (top-left global) coordinates.
    ///   - gesture: pointer locations in Cocoa screen coordinates.
    static func admits(axBounds: CGRect?, gesture: Gesture, screens: ScreenLayout) -> Bool {
        // Chromium answers some ranges (a paragraph ending in a line break) with a 1×1 rect at
        // an unrelated position; a rect too small to hold a glyph says nothing about location.
        guard let axBounds, !axBounds.isNull, !axBounds.isInfinite,
              axBounds.width >= minimumMeaningfulSide, axBounds.height >= minimumMeaningfulSide else { return true }
        let bounds = CGRect(
            x: axBounds.minX,
            y: screens.primaryMaxY - axBounds.maxY,
            width: axBounds.width,
            height: axBounds.height
        )
        // Some AX providers report bounds in a space that maps nowhere on screen; that says
        // nothing about where the selection is.
        guard screens.frames.contains(where: { $0.intersects(bounds) }) else { return true }
        return bounds.intersects(zone(for: gesture))
    }

    static func zone(for gesture: Gesture) -> CGRect {
        let rect: CGRect
        switch gesture {
        case .multiClick(let point):
            rect = CGRect(origin: point, size: .zero)
        case .drag(let start, let end):
            rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
        }
        let verticalTolerance: CGFloat = switch gesture {
        case .multiClick: tolerance
        case .drag: dragVerticalTolerance
        }
        return rect.insetBy(dx: -tolerance, dy: -verticalTolerance)
    }
}
