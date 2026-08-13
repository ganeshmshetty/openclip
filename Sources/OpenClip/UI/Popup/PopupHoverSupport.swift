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

    /// Applies the action's title as the OS tooltip. (The hover preview strip is gone with the
    /// canvas feature, so there is nothing to suppress tooltips for anymore.)
    @MainActor
    func applyContentTooltip(for action: any Action, fallback: String) -> some View {
        self.help(fallback)
    }
}
