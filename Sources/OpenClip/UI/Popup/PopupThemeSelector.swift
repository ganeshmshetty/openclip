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
import Core

@MainActor
struct PopupThemeSelector: View {
    @AppStorage(SettingKey.popupTheme.name) private var theme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @AppStorage(SettingKey.popupScale.name) private var popupScale: Double = SettingKey.popupScale.defaultValue

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

    /// Shared tray geometry for both Theme and Mode rows.
    private var trayHeight: CGFloat { 34 }
    private var trayContentHeight: CGFloat { trayHeight - 6 }
    private var segmentWidth: CGFloat { 72 }
    private var modeSegmentWidth: CGFloat { 48 }

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
                sizeRow
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
            rowTitle(icon: "circle.lefthalf.filled", title: "Mode", subtitle: "System, Light or Dark appearance")
            Spacer()
            iconTiles(
                options: appearanceOptions,
                isSelected: { activeAppearance == $0.value },
                select: selectAppearance
            )
        }
        .padding(.vertical, 4)
    }

    private var sizeRow: some View {
        HStack(spacing: 12) {
            rowTitle(
                icon: "arrow.up.left.and.arrow.down.right",
                title: "Size",
                subtitle: "\(Int(round(popupScale * 100)))% scaling"
            )
            Spacer()
            HStack(spacing: 10) {
                Slider(value: $popupScale, in: 0.8...1.2, step: 0.05)
                    .frame(width: 140)
                Button("Reset") {
                    popupScale = 1.0
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
                .opacity(popupScale == 1.0 ? 0.4 : 1.0)
                .disabled(popupScale == 1.0)
            }
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

    /// Icon-only segments for the Mode row matching the theme row size.
    private func iconTiles(
        options: [AppearanceOption],
        isSelected: @escaping (AppearanceOption) -> Bool,
        select: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                if option.value != options[0].value {
                    hairline(height: 20)
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
        .frame(height: trayHeight)
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
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: modeSegmentWidth, height: trayContentHeight)
                .contentShape(Rectangle())
                .help(label)
                .accessibilityLabel(label)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
