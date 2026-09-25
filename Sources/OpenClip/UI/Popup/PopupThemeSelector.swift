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
    @Setting(SettingKey.contextualActionsEnabled) private var contextualActionsEnabled
    @Setting(SettingKey.disabledContextualActionIDs) private var disabledContextualActionIDs

    @State private var isShowingContextualPopover = false

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
        popupVerticalPosition == SettingKey.popupVerticalPosition.defaultValue &&
        contextualActionsEnabled == SettingKey.contextualActionsEnabled.defaultValue &&
        disabledContextualActionIDs == SettingKey.disabledContextualActionIDs.defaultValue
    }

    private func resetToDefaults() {
        theme = SettingKey.popupTheme.defaultValue
        themeColor = SettingKey.popupThemeColor.defaultValue
        popupScale = SettingKey.popupScale.defaultValue
        barWidthLevel = SettingKey.popupBarWidth.defaultValue
        popupAlignment = SettingKey.popupAlignment.defaultValue
        popupVerticalPosition = SettingKey.popupVerticalPosition.defaultValue
        contextualActionsEnabled = SettingKey.contextualActionsEnabled.defaultValue
        disabledContextualActionIDs = SettingKey.disabledContextualActionIDs.defaultValue
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

    var body: some View {
        VStack(spacing: 20) {
            SettingsCard("Theme & Style") {
                // The section's one and only preview: full width, above the controls, so it reads
                // as the result of everything below it rather than a decoration beside a row.
                PopupSwatch()
                    .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                    .padding(.vertical, SettingsDesignTokens.sectionCardPaddingV)

                SettingsDivider()

                appearanceControlRow(
                    title: "Popup Theme",
                    info: "Classic is a solid, opaque card. Glass blurs and tints what sits behind the popup."
                ) {
                    segmentedPicker(selection: themeSelection, options: themeOptions, label: "Popup Theme", width: 200)
                }

                SettingsDivider()

                appearanceControlRow(
                    title: "Color Mode",
                    info: "Follow the system appearance, or pin the popup to light or dark regardless of the Mac."
                ) {
                    iconPicker(selection: $themeColor, options: appearanceOptions, label: "Color Mode", width: 200)
                }
            }

            SettingsCard("Position & Sizing") {
                SettingsRow(
                    title: "Horizontal Position"
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
                    title: "Vertical Position"
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
                    title: "Popup Scale"
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

            }

            SettingsCard("Behavior") {
                SettingsRow(
                    title: "Contextual Actions",
                    subtitle: "Show relevant actions first based on what you select."
                ) {
                    HStack(spacing: 8) {
                        Button {
                            isShowingContextualPopover.toggle()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(contextualActionsEnabled ? SettingsDesignTokens.primaryText : SettingsDesignTokens.tertiaryText)
                                .frame(width: 24, height: 24)
                                .settingsGlassCircle()
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!contextualActionsEnabled)
                        .help(String(localized: "Configure Contextual Actions"))
                        .popover(isPresented: $isShowingContextualPopover, arrowEdge: .top) {
                            ContextualActionsPopoverView()
                        }

                        Toggle("", isOn: $contextualActionsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Enable Contextual Actions"))
                    }
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

    /// A settings row for the appearance controls: the shared label style (icon tile + title) with
    /// an info button beside it, and the segmented control on the trailing edge. Mirrors
    /// `SettingsRow`'s spacing and padding so the section keeps the app's row rhythm.
    private func appearanceControlRow<Control: View>(
        title: LocalizedStringKey,
        info: LocalizedStringKey,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            SettingsRowLabel(title: title)
            SettingsInfoButton(title: title, info: info)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
        .padding(.vertical, SettingsDesignTokens.sectionCardPaddingV)
        .frame(minHeight: 34)
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

/// A small info glyph that reveals an explanation in a popover, and shows the title as a native
/// hover tooltip. Owns its own presentation state so a row does not have to.
@MainActor
private struct SettingsInfoButton: View {
    let title: LocalizedStringKey
    let info: LocalizedStringKey

    @State private var isShowingInfo = false

    var body: some View {
        Image(systemName: "info.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .contentShape(Circle())
            .onTapGesture { isShowingInfo.toggle() }
            .help(title)
            .accessibilityLabel(title)
            .popover(isPresented: $isShowingInfo, arrowEdge: .bottom) {
                Text(info)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(14)
            }
    }
}
