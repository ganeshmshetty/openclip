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

    /// The stored value carries legacy category names; the picker only ever
    /// deals in the two current ones.
    private var themeSelection: Binding<String> {
        Binding(
            get: { isGlassOn ? "glass" : "classic" },
            set: { theme = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Popup Theme", systemImage: "paintbrush.fill") {
                    segmentedPicker(
                        selection: themeSelection,
                        options: themeOptions,
                        label: "Popup Theme",
                        width: 140
                    )
                }

                SettingsRow(title: "Color Mode", systemImage: "circle.lefthalf.filled") {
                    iconPicker(
                        selection: $themeColor,
                        options: appearanceOptions,
                        label: "Color Mode",
                        width: 120
                    )
                }

                SettingsRow(title: "Horizontal Position", systemImage: "text.alignleft") {
                    iconPicker(
                        selection: $popupAlignment,
                        options: alignmentOptions,
                        label: "Horizontal Position",
                        width: 120
                    )
                }

                SettingsRow(title: "Vertical Position", systemImage: "arrow.up.and.down") {
                    segmentedPicker(
                        selection: $popupVerticalPosition,
                        options: verticalPositionOptions,
                        label: "Vertical Position",
                        width: 190
                    )
                }

                SettingsRow(title: "Popup Scale", systemImage: "arrow.up.left.and.arrow.down.right") {
                    stepSlider(
                        value: Binding(
                            get: { popupScale },
                            set: { popupScale = $0 }
                        ),
                        accessibilityLabel: "Popup Scale"
                    )
                }

                SettingsRow(title: "Popup Width", systemImage: "arrow.left.and.right") {
                    stepSlider(
                        value: Binding(
                            get: { barWidthLevel },
                            set: { barWidthLevel = $0 }
                        ),
                        accessibilityLabel: "Popup Width"
                    )
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .disabled(isAllDefault)
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
    }

    private func segmentedPicker(
        selection: Binding<String>,
        options: [AppearanceOption],
        label: LocalizedStringKey,
        width: CGFloat
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
        width: CGFloat = 120
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

    /// Both size rows are the same 1-5 slider with its value parked at the end.
    private func stepSlider(
        value: Binding<Int>,
        accessibilityLabel: LocalizedStringKey
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
            .accessibilityValue("\(value.wrappedValue)")
            .frame(width: 140)
            Text("\(value.wrappedValue)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
        }
        .frame(height: 24)
    }
}
