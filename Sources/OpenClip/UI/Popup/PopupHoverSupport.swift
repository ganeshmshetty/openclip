// PopupHoverSupport.swift
// OpenClip
//
// Shared hover-state plumbing for the popup: the global hover location singleton, the
// hover-target model, the frame preference key used to track row frames in popup space,
// and the small view helpers that tag/annotate hoverable rows. Split out of PopupView.swift.
import SwiftUI
import Core

@MainActor
public final class PopupHoverState: ObservableObject {
    public static let shared = PopupHoverState()

    @Published public var location: CGPoint?
    @Published public var usesGlobalMouseMonitoring = false

    public init() {}
}

enum PopupHoverTarget: Hashable {
    case action(Int)
    case completion(Int)
    case chevron(String)
    case search
}

struct PopupHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [PopupHoverTarget: CGRect] = [:]

    static func reduce(value: inout [PopupHoverTarget: CGRect], nextValue: () -> [PopupHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PopupContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func popupHoverTarget(_ target: PopupHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }

    /// Applies the action's title as the tooltip. (Replaced native help with custom overlay in PopupView)
    @MainActor
    func applyContentTooltip(for action: any Action, fallback: String) -> some View {
        self
    }
}

struct PopupTooltipPreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// A lightweight, native-styled tooltip overlay for the floating popup.
struct PopupTooltipView: View {
    let text: String
    var effectiveTheme: String = "glass"
    var isDark: Bool = true
    var maxWidth: CGFloat? = nil

    private var textColor: Color {
        isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.85)
    }

    private var backgroundColor: Color {
        isDark ? Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.95) : Color.white.opacity(0.95)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .fixedSize(horizontal: true, vertical: true)
            .allowsHitTesting(false)
    }
}

/// A container that dynamically positions the tooltip above the hovered button and aligns it to
/// the bar's edges when near either end to prevent any clipping without altering bar padding.
struct PopupTooltipContainer: View {
    let text: String
    let targetFrame: CGRect
    let containerWidth: CGFloat
    let effectiveTheme: String
    let isDark: Bool

    @State private var tooltipSize: CGSize = .zero

    var body: some View {
        PopupTooltipView(
            text: text,
            effectiveTheme: effectiveTheme,
            isDark: isDark,
            maxWidth: max(40, containerWidth - 32)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PopupTooltipPreferenceKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(PopupTooltipPreferenceKey.self) { size in
            tooltipSize = size
        }
        .position(
            x: calculatedX,
            y: max(tooltipSize.height / 2 + 1, targetFrame.minY - tooltipSize.height / 2 - 3)
        )
    }

    private var calculatedX: CGFloat {
        guard tooltipSize.width > 0 else { return targetFrame.midX }
        let halfW = tooltipSize.width / 2
        let minAllowed = 16 + halfW
        let maxAllowed = max(minAllowed, containerWidth - 16 - halfW)

        // If the tooltip would overflow the right edge of the bar, align its trailing edge with the bar trailing edge
        if targetFrame.midX + halfW > containerWidth - 16 {
            return maxAllowed
        }
        // If the tooltip would overflow the left edge of the bar, align its leading edge with the bar leading edge
        if targetFrame.midX - halfW < 16 {
            return minAllowed
        }
        // Otherwise center directly over the target
        return targetFrame.midX
    }
}
