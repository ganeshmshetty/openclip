// SubBarAim.swift
// OpenClip
//
// Menu-aim for an open group sub-bar. The safe triangle runs from the pointer's previous
// position to the sub-bar edge that faces it — the same corridor that already keeps the
// row open while the pointer crosses a neighboring non-group button. An adjacent group
// replaces the row only after the pointer leaves that triangle or rests on the button.
import CoreGraphics
import Foundation

public enum SubBarAim {
    /// What an adjacent group hover should do to the open sub-bar.
    /// `keepMovingToward` restarts the rest timer; `keepResting` leaves it alone.
    public enum Decision: Equatable {
        case keepMovingToward
        case keepResting
        case switchToHovered
    }

    /// Stillness on an adjacent group before that group replaces the open sub-bar.
    public static let switchDwell: TimeInterval = 0.20

    /// Travel shorter than this is tracker jitter, not a change of aim.
    public static let movementEpsilon: CGFloat = 2

    /// Widens the sub-bar edge so a pointer aimed at a corner still counts as toward the row.
    private static let cornerTolerance: CGFloat = 8

    /// `rested` is how long the pointer has been still. Movement inside the triangle keeps the open row.
    public static func decision(
        previous: CGPoint?,
        current: CGPoint,
        subBarRect: CGRect,
        rested: TimeInterval,
        dwell: TimeInterval = switchDwell
    ) -> Decision {
        if rested >= dwell {
            return .switchToHovered
        }
        guard let previous else { return .keepResting }
        if hypot(current.x - previous.x, current.y - previous.y) < movementEpsilon {
            return .keepResting
        }
        if movesInsideTriangle(from: previous, to: current, subBarRect: subBarRect) {
            return .keepMovingToward
        }
        return .switchToHovered
    }

    /// True when `current` lies in the triangle whose apex is `previous` and whose base is the near edge of `subBarRect`.
    static func movesInsideTriangle(from previous: CGPoint, to current: CGPoint, subBarRect: CGRect) -> Bool {
        guard subBarRect.width > 0, subBarRect.height > 0, !subBarRect.contains(previous) else { return false }
        let corners = facingCorners(of: subBarRect, from: previous)
        return point(current, inTriangle: previous, corners.0, corners.1)
    }

    /// The sub-bar edge closest to a pointer that is above or below the row. A pointer beside the row uses that side.
    private static func facingCorners(of rect: CGRect, from point: CGPoint) -> (CGPoint, CGPoint) {
        let tolerance = cornerTolerance
        if point.y > rect.maxY {
            return (
                CGPoint(x: rect.minX - tolerance, y: rect.maxY),
                CGPoint(x: rect.maxX + tolerance, y: rect.maxY)
            )
        }
        if point.y < rect.minY {
            return (
                CGPoint(x: rect.minX - tolerance, y: rect.minY),
                CGPoint(x: rect.maxX + tolerance, y: rect.minY)
            )
        }
        if point.x >= rect.midX {
            return (
                CGPoint(x: rect.maxX, y: rect.minY - tolerance),
                CGPoint(x: rect.maxX, y: rect.maxY + tolerance)
            )
        }
        return (
            CGPoint(x: rect.minX, y: rect.minY - tolerance),
            CGPoint(x: rect.minX, y: rect.maxY + tolerance)
        )
    }

    private static func point(_ p: CGPoint, inTriangle a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let v0x = c.x - a.x, v0y = c.y - a.y
        let v1x = b.x - a.x, v1y = b.y - a.y
        let v2x = p.x - a.x, v2y = p.y - a.y
        let dot00 = v0x * v0x + v0y * v0y
        let dot01 = v0x * v1x + v0y * v1y
        let dot02 = v0x * v2x + v0y * v2y
        let dot11 = v1x * v1x + v1y * v1y
        let dot12 = v1x * v2x + v1y * v2y
        let denom = dot00 * dot11 - dot01 * dot01
        if abs(denom) < 0.000_001 { return false }
        let inv = 1 / denom
        let u = (dot11 * dot02 - dot01 * dot12) * inv
        let v = (dot00 * dot12 - dot01 * dot02) * inv
        let slack: CGFloat = 0.000_1
        return u >= -slack && v >= -slack && (u + v) <= 1 + slack
    }
}
