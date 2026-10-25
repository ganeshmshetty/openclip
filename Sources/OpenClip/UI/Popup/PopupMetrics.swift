// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel and the action-search
// palette. These are presentation concerns — they live in the App target (not `Core`) so
// `Sources/Core/` stays free of UI vocabulary. The popup panel and every view that sizes the
// popup reads from here.
import CoreGraphics
import Foundation
import SwiftUI
import AppKit

public enum PopupMetrics {
    /// Brief grace for OCR popups: recognition can outlast the cursor leaving the release point.
    static let ocrArrivalDismissalGrace: TimeInterval = 1.0
    /// Standard width and height of an action button in the popup bar and sub-bar (normalized baseline at 1.0 scale).
    public static let actionButtonWidth: CGFloat = 39.0
    public static let barButtonHeight: CGFloat = 33.5
    /// Maximum baseline width (pt at 1.0 scale) for an inline result button in the bar.
    public static let inlineResultMaxWidth: CGFloat = 172.0
    /// Horizontal padding (pt at 1.0 scale) inside an expanded inline result button.
    public static let inlineResultHorizontalPadding: CGFloat = 9.0
    /// Row inset at each end of a group sub-bar; keeps the card-edge gap equal to the main bar's 3 pt.
    public static let subBarEndInset: CGFloat = 1.0
    /// Cross-fade between rest icon/text and computed result; long enough to hide async Tier 3 arrivals.
    public static let inlineCrossFadeDuration: Double = 0.22
    /// Spring response for inline button expansion; covers light-JS evaluation time.
    public static let inlineSpringResponse: Double = 0.22
    /// Spring damping for inline expansion; slight overshoot signals liveness for late results.
    public static let inlineSpringDamping: Double = 0.72

    /// Resolved spring animation or immediate cut respecting macOS Reduce Motion accessibility setting.
    public static func springOrImmediate(response: Double = 0.28, dampingFraction: Double = 0.8) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .linear(duration: 0.05)
        }
        return .spring(response: response, dampingFraction: dampingFraction)
    }

    /// Default spring for inline expansions, falling back to an immediate linear cut under Reduce Motion.
    public static var inlineSpring: Animation {
        springOrImmediate(response: inlineSpringResponse, dampingFraction: inlineSpringDamping)
    }
    /// Hard execution timeout for inline evaluation; covers p99 heavy JS with margin.
    public static let inlineEvaluationTimeout: TimeInterval = 0.90
    /// Maximum width (pt at 1.0 scale) for the trailing inline accessory in the search palette.
    public static let inlineSearchAccessoryMaxWidth: CGFloat = 120.0
    public static let popupCornerRadius: CGFloat = 14.0
    public static let cardCornerRadius: CGFloat = 22.0
    /// Corner radius for the action-search palette, reduced by 2 pt from the shared card radius.
    public static let searchCornerRadius: CGFloat = 20.0
    public static let searchRowCornerRadius: CGFloat = 10.0
    /// Shared radius for footer controls in the search palette and result card.
    public static let footerButtonCornerRadius: CGFloat = 10.0
    public static let toastCornerRadius: CGFloat = 14.0
    /// Maximum character length displayed in floating toast bubbles before truncating with an ellipsis.
    public static let toastMaxCharacterLength: Int = 40
    public static let toastAnchorGap: CGFloat = 8.0
    /// Prefer clearing the action/group bar above, without moving feedback far past a tall card.
    public static let toastPreferredAboveDistance: CGFloat = 140.0
    public static let captureStatusGap: CGFloat = 6.0
    /// Transparent ring so the toast drop shadow is not clipped; excluded from hit-testing.
    public static let toastShadowInset: CGFloat = 8.0
    public static let popupPadding: CGFloat = 8.0
    /// Gap between the prioritized contextual actions island and the standard actions island in the split popup bar.
    public static let splitIslandGap: CGFloat = 9.0
    /// Card drop-shadow geometry, mirrored by `PopupCardChromeModifier` (`PopupThemeModel.swift`). The panel's transparent ring must cover the blur tail or the frame clips it.
    public static let cardShadowContactRadius: CGFloat = 1.5
    public static let cardShadowContactYOffset: CGFloat = 1.0
    public static let cardShadowAmbientRadius: CGFloat = 12.0
    public static let cardShadowAmbientYOffset: CGFloat = 4.0
    /// Measured SwiftUI shadow tail: alpha stays visible to about `yOffset + factor * radius`.
    private static let cardShadowTailFactor: CGFloat = 2.0
    /// Transparent ring inside the panel frame so the drop shadow is not clipped.
    /// Excluded from hit-testing so clicks in the shadow fall through to the app underneath.
    /// Keep in sync with PopupView's `.padding(popupShadowInset)`.
    public static let popupShadowInset: CGFloat = max(
        cardShadowAmbientRadius,
        cardShadowAmbientYOffset + cardShadowTailFactor * cardShadowAmbientRadius
    )
    /// Cursor distance (pt) beyond which the popup auto-dismisses (suspended in search/content mode).
    public static let popupDismissalDistance: CGFloat = 160.0
    /// Scales with screen width, between 180 and 280 pt.
    public static func dismissalDistance(for screenFrame: CGRect) -> CGFloat {
        max(180.0, min(screenFrame.width * 0.12, 280.0))
    }
    /// Screen-bottom threshold below which the card renders above the action bar (equals `popupDismissalDistance`).
    public static let cardAboveThreshold: CGFloat = 280.0
    /// Action-search palette sizing: content width, total panel width, visible result rows and result row height.
    public static let searchPanelContentWidth: CGFloat = 320.0
    public static var searchPanelWidth: CGFloat { searchPanelContentWidth + 2 * popupShadowInset }
    public static let searchMaxRows: Int = 6
    public static let searchResultRowHeight: CGFloat = 30
    /// Extra row fraction shown past `searchMaxRows` so the list visibly scrolls.
    public static let searchPeekRowFraction: CGFloat = 0.0
    /// Smallest width the palette allows; matches the default content width.
    public static let searchPaletteMinWidth: CGFloat = searchPanelContentWidth
    public static let searchPaletteMinHeight: CGFloat = 270.0
    /// Shared height cap for the popup panel; `PopupPanel.heightCap` lifts it while a resizable surface shows.
    public static let popupMaxHeight: CGFloat = 312
    /// Result card sizing: long responses scroll; resize may exceed the max up to the screen, but not the min.
    /// A user-resized size is persisted (`SettingKey.resultCardWidth`/`resultCardHeight`) and overrides the default.
    public static let aiCardMinWidth: CGFloat = 220
    public static let aiCardIdealWidth: CGFloat = 320
    public static let aiCardMaxWidth: CGFloat = 360
    public static let aiCardMinHeight: CGFloat = 200
    public static let aiCardMaxHeight: CGFloat = 280
    /// Scrollable body max height; keeps the card plus `popupShadowInset` under `popupMaxHeight` to avoid clipping.
    public static let aiCardBodyHeight: CGFloat = 170
    /// Additional-instruction prompt: fixed-width card whose editor scrolls past `instructionEditorHeight`.
    public static let instructionCardWidth: CGFloat = 340
    public static let instructionEditorHeight: CGFloat = 92
    /// Info/error toast auto-dismiss delay; loading toasts have no timer.
    public static let toastDurationNanoseconds: UInt64 = 1_200_000_000
    /// Ignores queued app-activation notifications right after a session starts; later ones are real focus switches.
    public static let focusSwitchGracePeriod: TimeInterval = 0.3

    /// Maps the 1...5 scale level to a multiplier; 3 is the default.
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

    /// Maximum screen fraction the popup bar can occupy before wrapping to the next page.
    public static let maxScreenFraction: CGFloat = 0.50

    public static func maxBarWidth(for screenWidth: CGFloat) -> CGFloat {
        screenWidth * maxScreenFraction
    }

    /// Maps the 1...5 bar width level to a baseline width budget (pt at 1.0 scale); 3 is the default.
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
