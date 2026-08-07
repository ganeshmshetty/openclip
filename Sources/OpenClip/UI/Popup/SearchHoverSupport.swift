// SearchHoverSupport.swift
// OpenClip
//
// Hover-target plumbing for the action-search palette (result rows + Esc keycap).
// Split out of PopupSearchView.swift; mirrors the bar's PopupHoverSupport pattern.
import SwiftUI
import Core

/// Hover targets within the action-search palette (result rows + Esc keycap).
enum SearchHoverTarget: Hashable {
    case row(Int)
    case esc
}

struct SearchHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SearchHoverTarget: CGRect] = [:]

    static func reduce(value: inout [SearchHoverTarget: CGRect], nextValue: () -> [SearchHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func searchHoverTarget(_ target: SearchHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }
}
