// GeneralTabView.swift
// OpenClip
//
// The General preferences tab: app enable and menu bar toggles, trigger hotkey,
// start-at-login, and system-permission status. Split out of PreferencesView.swift.
//
// Rows are stock grouped-`Form` controls: the system draws the card, the row
// metrics and the label/control split, so the tab tracks System Settings across
// appearance and accent changes without any local styling.
import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct GeneralTab: View {
    /// Backed by the settings store — the single owner of `isAppEnabled`. Seeded at init and kept
    /// in sync with external changes (status-bar toggle) via the shared state-changed notification.
    @State private var isAppEnabled: Bool
    @State private var showMenuBarIcon: Bool
    @State private var isMouseHoldEnabled: Bool
    @State private var primaryBehavior: String
    @State private var secondaryBehavior: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _showMenuBarIcon = State(initialValue: DefaultSettingsStore.shared.get(.showMenuBarIcon))
        _isMouseHoldEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isMouseHoldEnabled))
        _primaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.primaryClickBehavior))
        _secondaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.secondaryClickBehavior))
    }
    
    var body: some View {
        Form {
            // Everything that decides how the popup is summoned sits together,
            // shortcut included — it used to be stranded between switches that
            // had nothing to do with triggering.
            Section("Triggers") {
                SettingsToggleRow(
                    title: "Appear Automatically",
                    subtitle: "Show the popup as soon as text is selected.",
                    systemImage: "cursorarrow",
                    isOn: $isAppEnabled
                )
                .onChange(of: isAppEnabled) { _, newValue in
                    DefaultSettingsStore.shared.set(.isAppEnabled, value: newValue)
                    NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenClipEnabledStateChanged"))) { notification in
                    isAppEnabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
                }

                SettingsToggleRow(
                    title: "Hold Mouse to Trigger",
                    subtitle: "Keep the button down after selecting to summon the popup.",
                    systemImage: "hand.tap",
                    isOn: $isMouseHoldEnabled
                )
                .onChange(of: isMouseHoldEnabled) { _, newValue in
                    DefaultSettingsStore.shared.set(.isMouseHoldEnabled, value: newValue)
                }

                SettingsRow(
                    title: "Keyboard Shortcut",
                    subtitle: "Summon the popup for whatever is selected.",
                    systemImage: "keyboard"
                ) {
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }

                SettingsRow(
                    title: "Instant AI Shortcut",
                    subtitle: "Type what AI should do with the selection; ⏎ replaces it with the answer.",
                    systemImage: "bolt"
                ) {
                    KeyboardShortcuts.Recorder(for: .instantAI)
                }
            }

            Section("Action Results") {
                SettingsRow(
                    title: "Primary click",
                    subtitle: "Left click",
                    systemImage: "cursorarrow.click"
                ) {
                    resultPicker(selection: $primaryBehavior, label: "Primary click")
                        .onChange(of: primaryBehavior) { _, newValue in
                            DefaultSettingsStore.shared.set(.primaryClickBehavior, value: newValue)
                        }
                }

                SettingsRow(
                    title: "Secondary click",
                    subtitle: "Right click or ⇧-click",
                    systemImage: "cursorarrow.click.2"
                ) {
                    resultPicker(selection: $secondaryBehavior, label: "Secondary click")
                        .onChange(of: secondaryBehavior) { _, newValue in
                            DefaultSettingsStore.shared.set(.secondaryClickBehavior, value: newValue)
                        }
                }
            }

            Section("App") {
                SettingsToggleRow(
                    title: "Show Menu Bar Icon",
                    systemImage: "menubar.rectangle",
                    isOn: $showMenuBarIcon
                )
                .onChange(of: showMenuBarIcon) { _, newValue in
                    DefaultSettingsStore.shared.set(.showMenuBarIcon, value: newValue)
                    NotificationCenter.default.post(
                        name: .openClipMenuBarVisibilityChanged,
                        object: newValue
                    )
                }

                SettingsToggleRow(
                    title: "Start at Login",
                    systemImage: "arrow.clockwise.circle",
                    isOn: $launchManager.isEnabled
                )
            }

            Section("Permissions") {
                SettingsRow(
                    title: "Accessibility Access",
                    subtitle: "Required to read the selected text.",
                    systemImage: "lock.shield"
                ) {
                    HStack(spacing: 10) {
                        Label {
                            Text(permissionManager.isAccessibilityGranted
                                 ? String(localized: "Granted")
                                 : String(localized: "Access Required"))
                        } icon: {
                            Image(systemName: permissionManager.isAccessibilityGranted
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(permissionManager.isAccessibilityGranted ? Color.green : Color.orange)

                        Button("Open Settings") {
                            // Only proactively reset stale TCC when permission is missing.
                            // Resetting while already granted would revoke the active entry.
                            let shouldReset = !permissionManager.isAccessibilityGranted
                            permissionManager.requestAccessibilityPermission(proactivelyResetStaleTCC: shouldReset)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }

    /// Both click rows offer the same three outcomes, at a width that fits the
    /// longest of them without stretching across the row.
    private func resultPicker(selection: Binding<String>, label: LocalizedStringKey) -> some View {
        Picker("", selection: selection) {
            ForEach(ResultDeliveryPreference.allCases, id: \.self) { pref in
                Text(LocalizedStringKey(pref.rawValue.capitalized)).tag(pref.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 230)
        .accessibilityLabel(label)
    }
}
