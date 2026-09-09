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
                Picker(selection: themeSelection) {
                    ForEach(themeOptions) { option in
                        Text(LocalizedStringKey(option.label)).tag(option.value)
                    }
                } label: {
                    SettingsRowLabel(title: "Popup Theme", systemImage: "paintbrush.fill")
                }
                .pickerStyle(.segmented)

                Picker(selection: $themeColor) {
                    ForEach(appearanceOptions) { option in
                        Image(systemName: option.icon)
                            .help(LocalizedStringKey(option.label))
                            .accessibilityLabel(LocalizedStringKey(option.label))
                            .tag(option.value)
                    }
                } label: {
                    SettingsRowLabel(title: "Color Mode", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.segmented)

                Picker(selection: $popupAlignment) {
                    ForEach(alignmentOptions) { option in
                        Image(systemName: option.icon)
                            .help(LocalizedStringKey(option.label))
                            .accessibilityLabel(LocalizedStringKey(option.label))
                            .tag(option.value)
                    }
                } label: {
                    SettingsRowLabel(title: "Horizontal Position", systemImage: "text.alignleft")
                }
                .pickerStyle(.segmented)

                Picker(selection: $popupVerticalPosition) {
                    ForEach(verticalPositionOptions) { option in
                        Text(LocalizedStringKey(option.label)).tag(option.value)
                    }
                } label: {
                    SettingsRowLabel(title: "Vertical Position", systemImage: "arrow.up.and.down")
                }
                .pickerStyle(.segmented)

                LabeledContent {
                    stepSlider(
                        value: Binding(
                            get: { popupScale },
                            set: { popupScale = $0 }
                        ),
                        accessibilityLabel: "Popup Scale"
                    )
                } label: {
                    SettingsRowLabel(
                        title: "Popup Scale",
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }

                LabeledContent {
                    stepSlider(
                        value: Binding(
                            get: { barWidthLevel },
                            set: { barWidthLevel = $0 }
                        ),
                        accessibilityLabel: "Popup Width"
                    )
                } label: {
                    SettingsRowLabel(title: "Popup Width", systemImage: "arrow.left.and.right")
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
    }
}
