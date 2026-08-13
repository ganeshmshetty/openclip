// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel and the action-search
// palette. These are presentation concerns — they live in the App target (not `Core`) so
// `Sources/Core/` stays free of UI vocabulary. The popup panel and every view that sizes the
// popup reads from here.
import CoreGraphics

public enum PopupMetrics {
    public static let popupPadding: CGFloat = 8.0
    /// Cursor distance (pt) beyond which the popup auto-dismisses (suspended in search/content mode).
    public static let popupDismissalDistance: CGFloat = 160.0
    /// Vertical threshold (pt) from the bottom of the screen bounds below which the card renders
    /// above the action bar instead of below (numerically equals `popupDismissalDistance`).
    public static let cardAboveThreshold: CGFloat = 280.0
    /// Action-search palette sizing: visible result rows and result row height.
    public static let searchMaxRows: Int = 5
    public static let searchResultRowHeight: CGFloat = 32
    /// Fraction of an extra result row shown beyond `searchMaxRows` so the next action peeks,
    /// hinting that the list scrolls.
    public static let searchPeekRowFraction: CGFloat = 0.5
    /// Shared height cap for the popup panel (search palette field + result rows). The code value
    /// 240 wins over any stale comment.
    public static let popupMaxHeight: CGFloat = 240
    /// Native AI result card sizing: width clamped to the shared popup column and a max body
    /// height so a long response scrolls instead of growing the panel without bound.
    public static let aiCardMinWidth: CGFloat = 220
    public static let aiCardIdealWidth: CGFloat = 300
    public static let aiCardMaxWidth: CGFloat = 360
    /// The card's scrollable body region is a fixed height: a ScrollView with only `.maxHeight`
    /// reports a starved ideal height, so the panel would never grow to fit the response (the body
    /// collapsed to nothing while the header/footer rendered). A concrete height gives the card a
    /// deterministic preferred size and keeps the whole card under `popupMaxHeight`.
    public static let aiCardBodyHeight: CGFloat = 120
    /// How long an info/error toast stays up before auto-dismissing (0.5 s). Loading toasts have
    /// no timer — they live until the action's result lands.
    public static let toastDurationNanoseconds: UInt64 = 500_000_000
}