// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel, the action-search
// palette, and the content canvas. These are presentation concerns — they live in the App
// target (not `Core`) so `Sources/Core/` stays free of UI vocabulary. The popup panel and
// every view that sizes the popup reads from here.
import CoreGraphics

public enum PopupMetrics {
    public static let popupPadding: CGFloat = 8.0
    /// Cursor distance (pt) beyond which the popup auto-dismisses (suspended in search/content mode).
    public static let popupDismissalDistance: CGFloat = 280.0
    /// Vertical threshold (pt) from the bottom of the screen bounds below which the card renders
    /// above the action bar instead of below (numerically equals `popupDismissalDistance`).
    public static let cardAboveThreshold: CGFloat = 280.0
    /// Action-search palette sizing: visible result rows and result row height.
    public static let searchMaxRows: Int = 5
    public static let searchResultRowHeight: CGFloat = 32
    /// Fraction of an extra result row shown beyond `searchMaxRows` so the next action peeks,
    /// hinting that the list scrolls.
    public static let searchPeekRowFraction: CGFloat = 0.5
    /// Shared height cap for the popup panel (search palette field + result rows, and the canvas
    /// body). The code value 240 wins over any stale comment.
    public static let popupMaxHeight: CGFloat = 240
    /// Measured height of `CanvasHeaderView` (padding 8pt top/bottom + 16pt content height + 1pt hairline divider = 33pt).
    public static let canvasHeaderHeight: CGFloat = 33.0
    /// Delay before the inline hover-preview strip appears (400ms).
    public static let hoverPreviewDelayNanoseconds: UInt64 = 400_000_000
    /// Delay before the long-press result canvas fires (600ms).
    public static let longPressDelayNanoseconds: UInt64 = 600_000_000
}