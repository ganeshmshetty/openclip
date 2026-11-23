// AppearanceTabView.swift
// OpenClip
//
// The Appearance preferences tab: popup preview + theme selector.
// Styled to match the modern settings cards.

import SwiftUI
import Core

@MainActor
struct AppearanceTab: View {
    @ObservedObject private var router = SettingsRouter.shared
    @State private var highlightedControlID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // No separate preview stage: each appearance choice is shown by its own live
                    // swatch, so the pickers are the preview.
                    PopupThemeSelector(highlightedControlID: highlightedControlID)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task(id: router.appearanceRevealRequest?.id) {
                guard let request = router.appearanceRevealRequest else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(request.targetID, anchor: .center)
                }
                highlightedControlID = request.targetID
                do {
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    if router.appearanceRevealRequest?.id == request.id {
                        highlightedControlID = nil
                        router.clearAppearanceRevealRequest(request.id)
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                highlightedControlID = nil
                router.clearAppearanceRevealRequest(request.id)
            }
        }
    }
}
