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
                // The preview is a fixed-size stage, so it sits above the cards
                PopupPreview()

                PopupThemeSelector()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
