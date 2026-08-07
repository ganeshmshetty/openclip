// PopupThemeSelector.swift
// OpenClip
//
// Lets the user pick the popup appearance as a grouped settings section (matching
// the General tab's look). The Theme row picks the category — Classic (solid color
// themes) or Glass (the material). The Mode row picks that category's appearance:
// System/Light/Dark as square icon tiles, where System means follow the system
// appearance (the historical Glass behavior). Choosing a forced appearance fixes
// the low-contrast case where a light system renders near-white glass over a white
// background.
//
// Storage: "popupTheme" keeps the category ("classic"/"glass"); "popupThemeColor"
// keeps the shared appearance ("system"/"light"/"dark") used by both categories.
// Legacy values of "popupTheme" resolve via PopupThemeModel.category(fromStored:).
import SwiftUI

@MainActor
struct PopupThemeSelector: View {
    @AppStorage("popupTheme") private var theme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"

    private struct AppearanceOption: Identifiable {
        let label: String
        let value: String
        let icon: String
        var id: String { value }
    }

    private var category: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: theme)
    }

    private var isGlassOn: Bool { category == .glass }

    /// Tray geometry. The Theme tray hugs its segment text width at a compact height;
    /// the Mode tray is a bit taller so the appearance icon tiles have room to breathe.
    private var trayHeight: CGFloat { 34 }
    private var trayContentHeight: CGFloat { trayHeight - 6 }
    private var segmentWidth: CGFloat { 72 }
    private var tileWidth: CGFloat { 48 }
    private var tileHeight: CGFloat { 36 }
    private var tileTrayHeight: CGFloat { tileHeight + 6 }

    private var themeOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "Classic", value: "classic", icon: ""),
            AppearanceOption(label: "Glass", value: "glass", icon: "")
        ]
    }

    private var appearanceOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "System", value: "system", icon: "circle.lefthalf.filled"),
            AppearanceOption(label: "Light", value: "light", icon: "sun.max.fill"),
            AppearanceOption(label: "Dark", value: "dark", icon: "moon.fill")
        ]
    }

    private var activeAppearance: String {
        themeColor
    }

    private func selectAppearance(_ value: String) {
        themeColor = value
    }

    var body: some View {
        Form {
            Section {
                themeRow
                modeRow
            } footer: {
                Text("Applies to both themes. System follows the Mac's Light/Dark setting — pin Glass to Dark for a high-contrast popup over white backgrounds.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "paintbrush.fill", title: "Theme", subtitle: "Classic solid colors or glass material")
            Spacer()
            labelSegments(
                options: themeOptions,
                isSelected: { isGlassOn ? $0.value == "glass" : $0.value == "classic" },
                select: { theme = $0 }
            )
        }
        .padding(.vertical, 4)
    }

    private var modeRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "circle.lefthalf.filled", title: "Mode", subtitle: "System, Light or Dark — applies to both themes")
            Spacer()
            iconTiles(
                options: appearanceOptions,
                isSelected: { activeAppearance == $0.value },
                select: selectAppearance
            )
        }
        .padding(.vertical, 4)
    }

    private func rowTitle(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Label-only segments for the Theme row.
    private func labelSegments(
        options: [AppearanceOption],
        isSelected: @escaping (AppearanceOption) -> Bool,
        select: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                if option.value != options[0].value {
                    hairline(height: 20)
                }
                segmentButton(
                    label: option.label,
                    isSelected: isSelected(option),
                    action: { select(option.value) }
                )
            }
        }
        .padding(3)
        .frame(height: trayHeight)
        .background(segmentContainerBackground)
        .overlay(segmentContainerBorder)
    }

    /// Square icon tiles for the Mode row.
    private func iconTiles(
        options: [AppearanceOption],
        isSelected: @escaping (AppearanceOption) -> Bool,
        select: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                if option.value != options[0].value {
                    hairline(height: 24)
                }
                tileButton(
                    label: option.label,
                    icon: option.icon,
                    isSelected: isSelected(option),
                    action: { select(option.value) }
                )
            }
        }
        .padding(3)
        .frame(height: tileTrayHeight)
        .background(segmentContainerBackground)
        .overlay(segmentContainerBorder)
    }

    private var segmentContainerBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private var segmentContainerBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    /// Thin separator between the segments/tiles within a tray.
    private func hairline(height: CGFloat = 14) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: height)
    }

    private func segmentButton(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: segmentWidth, height: trayContentHeight)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func tileButton(
        label: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(width: tileWidth, height: tileHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
