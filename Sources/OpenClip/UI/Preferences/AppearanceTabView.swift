// AppearanceTabView.swift
// OpenClip
//
// The Appearance settings page: a preview stage that shows either the popup bar or the
// action-search palette — a segmented switch above it picks which — and the theme selector below.
// Both previews are the real views in their static mode, so the stage is the theme, exactly.
import SwiftUI
import Core

/// Which surface the Appearance stage previews.
enum AppearancePreviewKind: String, CaseIterable, Identifiable, Sendable {
    case popup
    case palette

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .popup: return "Popup"
        case .palette: return "Palette"
        }
    }
}

@MainActor
struct AppearanceTab: View {
    @State private var previewKind: AppearancePreviewKind = .popup

    var body: some View {
        VStack(spacing: 0) {
            // The preview is a fixed-size stage, so it sits above the form
            // rather than inside it — a grouped row would stretch it.
            AppearancePreviewStage(kind: $previewKind)
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

/// The stage: a segmented control (the system's, so it picks up Liquid Glass on macOS 26) over
/// whichever preview is chosen, cross-fading between the two.
@MainActor
struct AppearancePreviewStage: View {
    @Binding var kind: AppearancePreviewKind

    var body: some View {
        VStack(spacing: 14) {
            Picker("Preview", selection: $kind) {
                ForEach(AppearancePreviewKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .accessibilityLabel("Preview")

            ZStack {
                switch kind {
                case .popup:
                    PopupPreview()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .palette:
                    PalettePreview()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.28), value: kind)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
