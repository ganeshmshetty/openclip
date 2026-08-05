// PopupThemeSelector.swift
// OpenClip
//
// Lets the user pick the popup appearance in two rows. Row one picks the theme
// category — Classic (solid color themes) or Glass (the material). Row two picks
// that category's appearance: System/Light/Dark for both, where System means follow
// the system appearance (the historical Glass behavior). Choosing a forced Glass
// appearance fixes the low-contrast case where a light system renders near-white
// glass over a white background.
//
// Storage: "popupTheme" keeps the category ("classic"/"glass"); "popupThemeColor"
// keeps the shared appearance ("system"/"light"/"dark") used by both categories.
// Legacy values of "popupTheme" resolve via PopupThemeModel.category(fromStored:).
import SwiftUI

@MainActor
struct PopupThemeSelector: View {
    @AppStorage("popupTheme") private var theme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"

    private struct AppearanceOption {
        let label: String
        let value: String
    }

    private var category: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: theme)
    }

    private var isGlassOn: Bool { category == .glass }

    private var appearanceOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "System", value: "system"),
            AppearanceOption(label: "Light", value: "light"),
            AppearanceOption(label: "Dark", value: "dark")
        ]
    }

    private var activeAppearance: String {
        themeColor
    }

    private func selectAppearance(_ value: String) {
        themeColor = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenClip Theme")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                segment(
                    label: "Classic",
                    isSelected: !isGlassOn
                ) {
                    theme = "classic"
                }

                divider

                segment(
                    label: "Glass",
                    isSelected: isGlassOn
                ) {
                    theme = "glass"
                }
            }
            .frame(maxWidth: .infinity)
            .padding(3)
            .background(segmentContainerBackground)
            .overlay(segmentContainerBorder)

            HStack(spacing: 0) {
                ForEach(Array(appearanceOptions.enumerated()), id: \.element.value) { index, option in
                    if index > 0 {
                        hairline
                    }
                    segment(
                        label: option.label,
                        isSelected: activeAppearance == option.value
                    ) {
                        selectAppearance(option.value)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(3)
            .background(segmentContainerBackground)
            .overlay(segmentContainerBorder)

            Text("Appearance applies to both themes. System follows the Mac's Light/Dark setting — pin Glass to Dark for a high-contrast popup over white backgrounds.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var segmentContainerBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private var segmentContainerBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    /// Thin separator between the appearance segments.
    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 14)
    }

    /// Prominent divider that groups the two theme categories apart.
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
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
