// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel and the action-search
// palette. These are presentation concerns — they live in the App target (not `Core`) so
// `Sources/Core/` stays free of UI vocabulary. The popup panel and every view that sizes the
// popup reads from here.
import CoreGraphics

public enum PopupMetrics {
    /// Corner radius for popup action bars and content cards (normalized baseline).
    public static let popupCornerRadius: CGFloat = 11.0
    /// Corner radius for the action-search palette.
    public static let searchCornerRadius: CGFloat = 10.0
    /// Corner radius for floating toast bubbles.
    public static let toastCornerRadius: CGFloat = 14.0
    /// Gap between a toast bubble and the popup edge it attaches to.
    public static let toastAnchorGap: CGFloat = 8.0
    public static let popupPadding: CGFloat = 8.0
    /// Transparent ring (pt) around the popup content *inside* the panel frame: `PopupView` pads
    /// its content by this amount so the SwiftUI drop shadow renders inside the panel edge instead
    /// of being clipped. The ring is excluded from mouse hit-testing by `PopupPanelContentView`
    /// so clicks in the visible shadow fall through to the app underneath (and dismiss the popup)
    /// instead of being silently swallowed by the panel frame. Keep in sync with PopupView's
    /// `.padding(popupShadowInset)`.
    public static let popupShadowInset: CGFloat = 16.0
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
    /// How long an info/error toast stays up before auto-dismissing (1.2 s — long enough to read
    /// "Copied"-style feedback). Loading toasts have no timer — they live until the action's
    /// result lands.
    public static let toastDurationNanoseconds: UInt64 = 1_200_000_000

    /// Converts a 1...5 discrete scale level to a visual scaling multiplier.
    /// Level 3 is the normal default (1.0).
    public static func scaleMultiplier(for level: Int) -> CGFloat {
        switch level {
        case 1: return 0.85
        case 2: return 0.925
        case 3: return 1.00
        case 4: return 1.10
        case 5: return 1.22
        default: return 1.00
        }
    }
}