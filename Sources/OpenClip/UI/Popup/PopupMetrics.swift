// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel and the action-search
// palette. These are presentation concerns — they live in the App target (not `Core`) so
// `Sources/Core/` stays free of UI vocabulary. The popup panel and every view that sizes the
// popup reads from here.
import CoreGraphics
import Foundation

public enum PopupMetrics {
    /// Standard width and height of an action button in the popup bar and sub-bar (normalized baseline at 1.0 scale).
    public static let actionButtonWidth: CGFloat = 34.0
    public static let barButtonHeight: CGFloat = 29.0
    /// Maximum baseline width (pt at 1.0 scale) for an inline result button in the bar.
    public static let inlineResultMaxWidth: CGFloat = 150.0
    /// Horizontal padding (pt at 1.0 scale) inside an expanded inline result button.
    public static let inlineResultHorizontalPadding: CGFloat = 8.0
    /// Cross-fade duration (seconds) between button rest icon/text and computed result.
    /// Benchmark (Tier 1 p95=0.01ms, Tier 2 p50=12.9ms): perceptual floor of 0.20s
    /// plus 2× Tier 2 p50 → 0.046s raw; rounded up to 0.05s, then bumped to 0.22s so
    /// results arriving from async Tier 3 don't snap in harshly. (was 0.18s)
    public static let inlineCrossFadeDuration: Double = 0.22
    /// Spring response duration for inline button expansion.
    /// Benchmark (Tier 3 light JS p90=137ms): 0.22s covers the light-JS band and
    /// gives the expand animation room to land while the result settles. (was 0.24s)
    public static let inlineSpringResponse: Double = 0.22
    /// Spring damping fraction for inline button expansion.
    /// Benchmark (Tier 3 medium JS p95=297ms): slight overshoot (0.72) signals
    /// liveness for results that arrive after a noticeable pause. (was 0.82)
    public static let inlineSpringDamping: Double = 0.72
    /// Hard execution timeout for inline action evaluation.
    /// Benchmark (Tier 3 heavy JS p99=737ms × 1.20 safety = 884ms → ceil 0.90s).
    /// Previous 0.50s cut off heavy JS at the p50; 0.90s covers p99 with margin. (was 0.50s)
    public static let inlineEvaluationTimeout: TimeInterval = 0.90
    /// Maximum width (pt at 1.0 scale) for the trailing inline accessory in the search palette.
    public static let inlineSearchAccessoryMaxWidth: CGFloat = 120.0
    /// Corner radius for popup action bars and sub-bars (normalized baseline).
    public static let popupCornerRadius: CGFloat = 12.0
    /// Corner radius for modal result cards and the action-search palette.
    public static let cardCornerRadius: CGFloat = 14.0
    /// Corner radius for the action-search palette.
    public static let searchCornerRadius: CGFloat = 14.0
    /// Corner radius for individual search palette result rows.
    public static let searchRowCornerRadius: CGFloat = 8.0
    /// Corner radius for floating toast bubbles.
    public static let toastCornerRadius: CGFloat = 14.0
    /// Maximum character length displayed in floating toast bubbles before truncating with an ellipsis.
    public static let toastMaxCharacterLength: Int = 40
    /// Gap between a toast bubble and the popup edge it attaches to.
    public static let toastAnchorGap: CGFloat = 8.0
    /// Transparent ring (pt) around the toast bubble inside the panel frame: the controller centers
    /// the bubble in a window inflated by this amount so its SwiftUI drop shadow (radius 4, y 1)
    /// renders instead of being clipped at the window edge — worst at the rounded corners, where the
    /// blur spreads diagonally. The whole toast panel ignores mouse events (it is purely a status
    /// surface), so the ring can never swallow clicks.
    public static let toastShadowInset: CGFloat = 8.0
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
    /// Dynamically scales dismissal distance based on screen width, scaling between 180pt and 280pt
    /// so the boundary is natural on both compact laptop screens and large desktop displays.
    public static func dismissalDistance(for screenFrame: CGRect) -> CGFloat {
        max(180.0, min(screenFrame.width * 0.12, 280.0))
    }
    /// Vertical threshold (pt) from the bottom of the screen bounds below which the card renders
    /// above the action bar instead of below (numerically equals `popupDismissalDistance`).
    public static let cardAboveThreshold: CGFloat = 280.0
    /// Action-search palette sizing: content width, total panel width, visible result rows and result row height.
    public static let searchPanelContentWidth: CGFloat = 300.0
    public static var searchPanelWidth: CGFloat { searchPanelContentWidth + 2 * popupShadowInset }
    public static let searchMaxRows: Int = 6
    public static let searchResultRowHeight: CGFloat = 32
    /// Fraction of an extra result row shown beyond `searchMaxRows` so the next action peeks,
    /// hinting that the list scrolls.
    public static let searchPeekRowFraction: CGFloat = 0.0
    /// Smallest size the palette's resize handles allow: compacts to the default search bar
    /// content width (300 pt) and default visible rows height (258 pt) that it has at first.
    public static let searchPaletteMinWidth: CGFloat = searchPanelContentWidth
    public static let searchPaletteMinHeight: CGFloat = 258.0
    /// Shared height cap for the popup panel (search palette field + result rows and content cards).
    /// Lifted per session via `PopupPanel.heightCap` while a resizable surface shows.
    public static let popupMaxHeight: CGFloat = 312
    /// Native result card sizing. The content-driven default is `aiCardIdealWidth` wide and
    /// between `aiCardMinHeight` and `aiCardMaxHeight` tall, so a long response scrolls instead of
    /// growing the panel without bound. The card's right/bottom resize handles can take it past
    /// the maximums (up to the screen, see `PopupResizeGeometry`) but never below the
    /// minimums; a resized size is remembered (`SettingKey.resultCardWidth` / `resultCardHeight`)
    /// and replaces the content-driven default on the next card.
    public static let aiCardMinWidth: CGFloat = 220
    public static let aiCardIdealWidth: CGFloat = 320
    public static let aiCardMaxWidth: CGFloat = 360
    public static let aiCardMinHeight: CGFloat = 200
    public static let aiCardMaxHeight: CGFloat = 280
    /// The card's scrollable body region has a max height so a long response scrolls instead of
    /// growing the panel without bound. Clamped so that the card plus popupShadowInset stays under
    /// `popupMaxHeight` (312 pt), avoiding window clipping.
    public static let aiCardBodyHeight: CGFloat = 170
    /// How long an info/error toast stays up before auto-dismissing (1.2 s — long enough to read
    /// "Copied"-style feedback). Loading toasts have no timer — they live until the action's
    /// result lands.
    public static let toastDurationNanoseconds: UInt64 = 1_200_000_000
    /// How long after a session starts an app-activation notification does not dismiss the popup.
    /// macOS can deliver a queued activation for the destination app just after the popup opens —
    /// common when a clipboard manager dismisses itself. A later activation is a real focus switch.
    public static let focusSwitchGracePeriod: TimeInterval = 0.3

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

    /// Converts a 1...5 discrete bar width level to a maximum baseline width budget (pt at 1.0 scale).
    /// Level 3 is the standard default (540 pt).
    public static func barWidth(for level: Int) -> CGFloat {
        switch level {
        case 1: return 340.0
        case 2: return 440.0
        case 3: return 540.0
        case 4: return 650.0
        case 5: return 780.0
        default: return 540.0
        }
    }
}