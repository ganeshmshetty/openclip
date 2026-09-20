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
    @State private var fileSaveLocation: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    /// Initializes preference state from the shared settings store.
    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _showMenuBarIcon = State(initialValue: DefaultSettingsStore.shared.get(.showMenuBarIcon))
        _isMouseHoldEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isMouseHoldEnabled))
        _primaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.primaryClickBehavior))
        _secondaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.secondaryClickBehavior))
        _fileSaveLocation = State(initialValue: DefaultSettingsStore.shared.get(.fileSaveLocation))
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
                    subtitle: "Press and hold without moving the mouse to summon the popup.",
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

                SettingsRow(
                    title: "Save Location",
                    subtitleText: saveLocationSubtitleText,
                    systemImage: "folder"
                ) {
                    HStack(spacing: 8) {
                        if !fileSaveLocation.isEmpty {
                            Button {
                                fileSaveLocation = ""
                                DefaultSettingsStore.shared.set(.fileSaveLocation, value: "")
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Reset to Downloads"))
                        }
                        Button(String(localized: "Choose…")) {
                            chooseSaveLocation()
                        }
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

    private var saveLocationSubtitleText: Text {
        if fileSaveLocation.isEmpty {
            return Text("Downloads (Default)")
        }
        return Text(verbatim: (fileSaveLocation as NSString).abbreviatingWithTildeInPath)
    }

    /// Presents a directory picker and persists the selected file-output location.
    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Select default folder for saved files")
        if !fileSaveLocation.isEmpty {
            let expanded = (fileSaveLocation as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        } else if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        if panel.runModal() == .OK, let chosenURL = panel.url {
            fileSaveLocation = chosenURL.path
            DefaultSettingsStore.shared.set(.fileSaveLocation, value: chosenURL.path)
        }
    }
}
