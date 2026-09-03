// AppearanceTabView.swift
// OpenClip
//
// The Appearance preferences tab: popup preview + theme selector.
// Split out of PreferencesView.swift.
import SwiftUI
import Core

@MainActor
struct AppearanceTab: View {
    var body: some View {
        VStack(spacing: 12) {
            PopupPreview()

            PopupThemeSelector()
        }
    }
}
