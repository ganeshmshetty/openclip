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
        VStack(spacing: 0) {
            // The preview is a fixed-size stage, so it sits above the form
            // rather than inside it — a grouped row would stretch it.
            PopupPreview()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            PopupThemeSelector()
        }
        // Fill the detail pane rather than settling at the content's own height:
        // a pane that only claims what it needs leaves the window sizing itself
        // differently per tab.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
