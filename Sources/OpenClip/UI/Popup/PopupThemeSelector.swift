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
    @AppStorage(SettingKey.popupScale.name) private var popupScale: Int = SettingKey.popupScale.defaultValue
    @AppStorage(SettingKey.popupBarWidth.name) private var barWidthLevel: Int = SettingKey.popupBarWidth.defaultValue
    @AppStorage(SettingKey.popupAlignment.name) private var popupAlignment: String = SettingKey.popupAlignment.defaultValue
    @AppStorage(SettingKey.popupVerticalPosition.name) private var popupVerticalPosition: String = SettingKey.popupVerticalPosition.defaultValue

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
    private var trayHeight: CGFloat { 26 }
    private var trayContentHeight: CGFloat { trayHeight - 4 }
    private var segmentWidth: CGFloat { 56 }
    private var modeSegmentWidth: CGFloat { 38 }

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

    private var alignmentOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "Left", value: "left", icon: "text.alignleft"),
            AppearanceOption(label: "Center", value: "center", icon: "text.aligncenter"),
            AppearanceOption(label: "Right", value: "right", icon: "text.alignright")
        ]
    }

    private var verticalPositionOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "Auto", value: "auto", icon: ""),
            AppearanceOption(label: "Above", value: "above", icon: ""),
            AppearanceOption(label: "Below", value: "below", icon: "")
        ]
    }

    private var activeAppearance: String {
        themeColor
    }

    private func selectAppearance(_ value: String) {
        themeColor = value
    }

    private var isAllDefault: Bool {
        theme == SettingKey.popupTheme.defaultValue &&
        themeColor == SettingKey.popupThemeColor.defaultValue &&
        popupScale == SettingKey.popupScale.defaultValue &&
        barWidthLevel == SettingKey.popupBarWidth.defaultValue &&
        popupAlignment == SettingKey.popupAlignment.defaultValue &&
        popupVerticalPosition == SettingKey.popupVerticalPosition.defaultValue
    }

    private func resetToDefaults() {
        theme = SettingKey.popupTheme.defaultValue
        themeColor = SettingKey.popupThemeColor.defaultValue
        popupScale = SettingKey.popupScale.defaultValue
        barWidthLevel = SettingKey.popupBarWidth.defaultValue
        popupAlignment = SettingKey.popupAlignment.defaultValue
        popupVerticalPosition = SettingKey.popupVerticalPosition.defaultValue
    }

    var body: some View {
        Form {
            Section {
                themeRow
                modeRow
                alignmentRow
                verticalPositionRow
                sizeRow
                barWidthRow
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .disabled(isAllDefault)
                    .opacity(isAllDefault ? 0.4 : 1.0)
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "paintbrush.fill", title: "Popup Theme")
            Spacer()
            labelSegments(
                options: themeOptions,
                isSelected: { isGlassOn ? $0.value == "glass" : $0.value == "classic" },
                select: { theme = $0 }
            )
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private var modeRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "circle.lefthalf.filled", title: "Color Mode")
            Spacer()
            iconTiles(
                options: appearanceOptions,
                isSelected: { activeAppearance == $0.value },
                select: selectAppearance
            )
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private var alignmentRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "text.alignleft", title: "Bar Alignment")
            Spacer()
            iconTiles(
                options: alignmentOptions,
                isSelected: { popupAlignment == $0.value },
                select: { popupAlignment = $0 }
            )
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private var verticalPositionRow: some View {
        HStack(spacing: 12) {
            rowTitle(icon: "arrow.up.and.down", title: "Vertical Position")
            Spacer()
            labelSegments(
                options: verticalPositionOptions,
                segmentWidth: 44,
                isSelected: { popupVerticalPosition == $0.value },
                select: { popupVerticalPosition = $0 }
            )
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private var sizeRow: some View {
        HStack(spacing: 12) {
            rowTitle(
                icon: "arrow.up.left.and.arrow.down.right",
                title: "Popup Scale"
            )
            Spacer()
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(popupScale) },
                        set: { popupScale = max(1, min(5, Int(round($0)))) }
                    ),
                    in: 1...5,
                    step: 1
                )
                .accessibilityLabel("Popup Scale")
                .accessibilityValue("\(popupScale)")
                .frame(width: 120)
                Text("\(popupScale)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private var barWidthRow: some View {
        HStack(spacing: 12) {
            rowTitle(
                icon: "arrow.left.and.right",
                title: "Bar Width"
            )
            Spacer()
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(barWidthLevel) },
                        set: { barWidthLevel = max(1, min(5, Int(round($0)))) }
                    ),
                    in: 1...5,
                    step: 1
                )
                .accessibilityLabel("Bar Width")
                .accessibilityValue("\(barWidthLevel)")
                .frame(width: 120)
                Text("\(barWidthLevel)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .frame(minHeight: 24)
        .padding(.vertical, 3)
    }

    private func rowTitle(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.accentColor)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.body)
                .fontWeight(.medium)
        }
    }

    /// Label-only segments for the Theme row.
    private func labelSegments(
        options: [AppearanceOption],
        segmentWidth: CGFloat = 56,
        isSelected: @escaping (AppearanceOption) -> Bool,
        select: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                if option.value != options[0].value {
                    hairline(height: 12)
                }
                segmentButton(
                    label: LocalizedStringKey(option.label),
                    width: segmentWidth,
                    isSelected: isSelected(option),
                    action: { select(option.value) }
                )
            }
        }
        .padding(2)
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
                    hairline(height: 12)
                }
                tileButton(
                    label: option.label,
                    icon: option.icon,
                    isSelected: isSelected(option),
                    action: { select(option.value) }
                )
            }
        }
        .padding(2)
        .frame(height: trayHeight)
        .background(segmentContainerBackground)
        .overlay(segmentContainerBorder)
    }

    private var segmentContainerBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.055))
    }

    private var segmentContainerBorder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    /// Thin separator between the segments/tiles within a tray.
    private func hairline(height: CGFloat = 14) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: height)
    }

    private func segmentButton(
        label: LocalizedStringKey,
        width: CGFloat = 56,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: width, height: trayContentHeight)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: modeSegmentWidth, height: trayContentHeight)
                .contentShape(Rectangle())
                .help(LocalizedStringKey(label))
                .accessibilityLabel(LocalizedStringKey(label))
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
