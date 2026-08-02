// PopupThemeSelector.swift
// OpenClip
//
// Lets the user pick the popup appearance in a single row: System/Light/Dark are the
// color themes, and Glass is grouped apart behind a divider because it is a material
// (no light/dark of its own — it adapts to the system appearance). Selecting a color
// turns Glass off, so the control always has exactly one active choice.
//
// Storage: "popupTheme" keeps the rendering value ("system"/"light"/"dark"/"glass")
// exactly as PopupView/BubbleCardView already expect; "popupThemeColor" remembers the
// last non-glass color choice so it can be restored when Glass is turned off.
import SwiftUI

@MainActor
struct PopupThemeSelector: View {
    @AppStorage("popupTheme") private var theme: String = "system"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"

    private struct ColorOption {
        let label: String
        let value: String
    }

    private let colorOptions = [
        ColorOption(label: "System", value: "system"),
        ColorOption(label: "Light", value: "light"),
        ColorOption(label: "Dark", value: "dark")
    ]

    private var isGlassOn: Bool { theme == "glass" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenClip Theme")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(colorOptions.enumerated()), id: \.element.value) { index, option in
                    if index > 0 {
                        hairline
                    }
                    segment(
                        label: option.label,
                        isSelected: !isGlassOn && themeColor == option.value
                    ) {
                        themeColor = option.value
                        theme = option.value
                    }
                }

                divider

                segment(label: "Glass", isSelected: isGlassOn) {
                    theme = isGlassOn ? themeColor : "glass"
                }
            }
            .frame(maxWidth: .infinity)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("Glass is a material that follows the system's Light/Dark appearance automatically.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// Thin separator between the color-theme segments.
    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 14)
    }

    /// Prominent divider that visually groups Glass apart from the color themes.
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.28))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 10)
    }

    private func segment(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
