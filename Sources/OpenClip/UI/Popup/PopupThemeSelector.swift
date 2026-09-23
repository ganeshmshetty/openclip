// PopupThemeSelector.swift
// OpenClip
//
// Lets the user pick the popup appearance as grouped settings sections (matching
// the General tab's look). Split into Theme & Style, and Position & Sizing cards.
//
// Styled with modern SettingsCard, icon tiles, and hairline dividers.

import SwiftUI
import Core

@MainActor
struct PopupThemeSelector: View {
    @Setting(SettingKey.popupTheme) private var theme
    @Setting(SettingKey.popupThemeColor) private var themeColor
    @Setting(SettingKey.popupScale) private var popupScale
    @Setting(SettingKey.popupBarWidth) private var barWidthLevel
    @Setting(SettingKey.popupAlignment) private var popupAlignment
    @Setting(SettingKey.popupVerticalPosition) private var popupVerticalPosition

    private struct AppearanceOption: Identifiable {
        let label: String
        let value: String
        var icon: String? = nil
        var id: String { value }
    }

    private var category: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: theme)
    }

    private var isGlassOn: Bool { category == .glass }

    private var themeOptions: [AppearanceOption] {
        [
            AppearanceOption(label: "Classic", value: "classic"),
            AppearanceOption(label: "Glass", value: "glass")
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
            AppearanceOption(label: "Auto", value: "auto"),
            AppearanceOption(label: "Above", value: "above"),
            AppearanceOption(label: "Below", value: "below")
        ]
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

    private var themeSelection: Binding<String> {
        Binding(
            get: { isGlassOn ? "glass" : "classic" },
            set: { theme = $0 }
        )
    }

    private func scaleLabel(for level: Int) -> String {
        switch level {
        case 1: return "85%"
        case 2: return "92%"
        case 3: return "100%"
        case 4: return "110%"
        case 5: return "122%"
        default: return "100%"
        }
    }

    private func widthLabel(for level: Int) -> String {
        switch level {
        case 1: return "Compact"
        case 2: return "Moderate"
        case 3: return "Default"
        case 4: return "Wide"
        case 5: return "Maximum"
        default: return "Default"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            SettingsCard("Theme & Style") {
                SettingsRow(
                    title: "Popup Theme",
                    systemImage: "paintbrush.fill",
                    iconTileTint: Color(red: 0.93, green: 0.28, blue: 0.60)
                ) {
                    segmentedPicker(
                        selection: themeSelection,
                        options: themeOptions,
                        label: "Popup Theme",
                        width: 170
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: "Color Mode",
                    systemImage: "sun.max.fill",
                    iconTileTint: Color(red: 0.96, green: 0.62, blue: 0.05)
                ) {
                    iconPicker(
                        selection: $themeColor,
                        options: appearanceOptions,
                        label: "Color Mode",
                        width: 170
                    )
                }
            }

            SettingsCard("Position & Sizing") {
                SettingsRow(
                    title: "Horizontal Position",
                    systemImage: "text.aligncenter",
                    iconTileTint: Color(red: 0.05, green: 0.72, blue: 0.85)
                ) {
                    iconPicker(
                        selection: $popupAlignment,
                        options: alignmentOptions,
                        label: "Horizontal Position",
                        width: 170
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: "Vertical Position",
                    systemImage: "arrow.up.and.down",
                    iconTileTint: Color(red: 0.20, green: 0.78, blue: 0.42)
                ) {
                    segmentedPicker(
                        selection: $popupVerticalPosition,
                        options: verticalPositionOptions,
                        label: "Vertical Position",
                        width: 170
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: "Popup Scale",
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    iconTileTint: Color(red: 0.98, green: 0.52, blue: 0.12)
                ) {
                    stepSlider(
                        value: Binding(
                            get: { popupScale },
                            set: { popupScale = $0 }
                        ),
                        accessibilityLabel: "Popup Scale",
                        labelText: scaleLabel(for: popupScale)
                    )
                }

                SettingsDivider()

                SettingsRow(
                    title: "Popup Width",
                    systemImage: "arrow.left.and.right",
                    iconTileTint: Color(red: 0.68, green: 0.35, blue: 0.98)
                ) {
                    stepSlider(
                        value: Binding(
                            get: { barWidthLevel },
                            set: { barWidthLevel = $0 }
                        ),
                        accessibilityLabel: "Popup Width",
                        labelText: widthLabel(for: barWidthLevel)
                    )
                }
            }

            HStack {
                Spacer()
                Button {
                    resetToDefaults()
                } label: {
                    Text(String(localized: "Reset"))
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .settingsGlassCapsule()
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isAllDefault ? SettingsDesignTokens.tertiaryText : SettingsDesignTokens.secondaryText)
                .disabled(isAllDefault)
            }
            .padding(.top, 2)
        }
    }

    private func segmentedPicker(
        selection: Binding<String>,
        options: [AppearanceOption],
        label: LocalizedStringKey,
        width: CGFloat = 170
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options) { option in
                Text(LocalizedStringKey(option.label)).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: width, height: 24)
        .accessibilityLabel(label)
    }

    private func iconPicker(
        selection: Binding<String>,
        options: [AppearanceOption],
        label: LocalizedStringKey,
        width: CGFloat = 170
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options) { option in
                if let icon = option.icon {
                    Image(systemName: icon)
                        .help(LocalizedStringKey(option.label))
                        .accessibilityLabel(LocalizedStringKey(option.label))
                        .tag(option.value)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: width, height: 24)
        .accessibilityLabel(label)
    }

    private func stepSlider(
        value: Binding<Int>,
        accessibilityLabel: LocalizedStringKey,
        labelText: String
    ) -> some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = max(1, min(5, Int(round($0)))) }
                ),
                in: 1...5,
                step: 1
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(labelText)
            .frame(width: 110)

            Text(labelText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(SettingsDesignTokens.secondaryText)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(width: 170, height: 24, alignment: .trailing)
    }
}
