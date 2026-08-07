// CanvasHoverSupport.swift
// OpenClip
//
// Hover-target plumbing for the content canvas chrome (currently just the Esc keycap).
// Split out of PopupContentView.swift; mirrors the bar's PopupHoverSupport pattern.
import SwiftUI
import Core

/// Hover targets within the content canvas chrome (currently just the Esc keycap).
enum CanvasHoverTarget: Hashable {
    case esc
}

struct CanvasHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CanvasHoverTarget: CGRect] = [:]

    static func reduce(value: inout [CanvasHoverTarget: CGRect], nextValue: () -> [CanvasHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Registers the receiver's frame in the popup's named hover space so the location-driven
    /// hit test can resolve it (same pattern as the bar and search palette).
    func canvasHoverTarget(_ target: CanvasHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }
}
