// AppearanceTabView.swift
// OpenClip
//
// The Appearance preferences tab: popup preview + theme selector.
// Styled to match the modern settings cards.

import SwiftUI
import Core

@MainActor
struct AppearanceTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // No separate preview stage: each appearance choice is shown by its own live
                // swatch, so the pickers are the preview.
                PopupThemeSelector()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
