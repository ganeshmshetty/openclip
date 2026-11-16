// PopupHoverSupport.swift
// OpenClip
//
// Shared hover-state plumbing for the popup: the global hover location singleton, the
// hover-target model, the frame preference key used to track row frames in popup space,
// and the small view helpers that tag/annotate hoverable rows. Split out of PopupView.swift.
import SwiftUI
import AppKit
import Core

@MainActor
public final class PopupHoverState: ObservableObject {
    public static let shared = PopupHoverState()

    @Published public var location: CGPoint?
    @Published public var usesGlobalMouseMonitoring = false
    /// Cursor the hovered surface wants. `PopupWindowController.updatePopupHover` applies this instead of a
    /// blanket arrow, so nested surfaces set one value per move rather than fighting the arrow on every event.
    /// Not `@Published`: it changes while the pointer moves and must not re-render observers.
    public var hoverCursor: NSCursor = .arrow

    public init() {}
}

@MainActor
public final class SubBarHoverState: ObservableObject {
    public static let shared = SubBarHoverState()

    @Published public var location: CGPoint?
    @Published public var usesGlobalMouseMonitoring = false

    public init() {}
}

public enum PopupHoverTarget: Hashable, Sendable {
    case action(Int)
    case subAction(Int)
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

/// A lightweight, native-styled tooltip bubble, rendered by TooltipPanelController in its own
/// screen-space window (TooltipPanel) so it is never clipped by the bar panels.
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
