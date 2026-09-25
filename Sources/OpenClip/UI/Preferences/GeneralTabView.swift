// GeneralTabView.swift
// OpenClip
//
// The General preferences tab: app enable and menu bar toggles, trigger hotkey,
// start-at-login, and system-permission status.
//
// Styled with inset SettingsCards (outside headers, rounded cards, inset hairline dividers).

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct GeneralTab: View {
    /// Backed by the settings store — the single owner of `isAppEnabled`.
    @State private var isAppEnabled: Bool
    @State private var showMenuBarIcon: Bool
    @State private var isMouseHoldEnabled: Bool
    @State private var fileSaveLocation: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    /// Initializes preference state from the shared settings store.
    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _showMenuBarIcon = State(initialValue: DefaultSettingsStore.shared.get(.showMenuBarIcon))
        _isMouseHoldEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isMouseHoldEnabled))
        _fileSaveLocation = State(initialValue: DefaultSettingsStore.shared.get(.fileSaveLocation))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Everything that decides how the popup is summoned sits together
                SettingsCard("Triggers") {
                    SettingsToggleRow(
                        title: "Appear Automatically",
                        subtitle: "Show the popup as soon as text is selected.",
                        systemImage: "cursorarrow",
                        plainIcon: true,
                        isOn: $isAppEnabled
                    )
                    .onChange(of: isAppEnabled) { _, newValue in
                        DefaultSettingsStore.shared.set(.isAppEnabled, value: newValue)
                        NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenClipEnabledStateChanged"))) { notification in
                        isAppEnabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Hold Mouse to Trigger",
                        subtitle: "Press and hold without moving the mouse to summon the popup.",
                        systemImage: "hand.tap",
                        plainIcon: true,
                        isOn: $isMouseHoldEnabled
                    )
                    .onChange(of: isMouseHoldEnabled) { _, newValue in
                        DefaultSettingsStore.shared.set(.isMouseHoldEnabled, value: newValue)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Keyboard Shortcut",
                        subtitle: "Summon the popup for whatever is selected.",
                        systemImage: "keyboard",
                        plainIcon: true
                    ) {
                        Shortcut(for: .togglePopup)
                    }
                }

                SettingsCard("Files") {
                    SettingsRow(
                        title: "Save Location",
                        subtitleText: saveLocationSubtitleText,
                        systemImage: "folder",
                        plainIcon: true
                    ) {
                        HStack(spacing: 8) {
                            if !fileSaveLocation.isEmpty {
                                Button {
                                    fileSaveLocation = ""
                                    DefaultSettingsStore.shared.set(.fileSaveLocation, value: "")
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(SettingsDesignTokens.secondaryText)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                                .settingsGlassCircle()
                                .contentShape(Circle())
                                .help(String(localized: "Reset to Downloads"))
                            }
                            Button(String(localized: "Choose…")) {
                                chooseSaveLocation()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }

                SettingsCard("App") {
                    SettingsToggleRow(
                        title: "Show Menu Bar Icon",
                        systemImage: "menubar.rectangle",
                        plainIcon: true,
                        isOn: $showMenuBarIcon
                    )
                    .onChange(of: showMenuBarIcon) { _, newValue in
                        DefaultSettingsStore.shared.set(.showMenuBarIcon, value: newValue)
                        NotificationCenter.default.post(
                            name: .openClipMenuBarVisibilityChanged,
                            object: newValue
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Start at Login",
                        systemImage: "arrow.clockwise.circle",
                        plainIcon: true,
                        isOn: $launchManager.isEnabled
                    )

                    if launchManager.requiresApproval {
                        SettingsDivider()
                        SettingsRow(
                            title: "Approval Required",
                            subtitle: "Enable OpenClip under System Settings > General > Login Items & Extensions.",
                            systemImage: "exclamationmark.triangle.fill",
                            plainIcon: true
                        ) {
                            Button(String(localized: "Open Settings")) {
                                launchManager.openLoginItemsSettings()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }

                SettingsCard("Permissions") {
                    SettingsRow(
                        title: "Accessibility Access",
                        subtitle: "Required to read the selected text.",
                        systemImage: "lock.shield",
                        plainIcon: true
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: permissionManager.isAccessibilityGranted
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(permissionManager.isAccessibilityGranted ? Color.green : Color.orange)
                                .accessibilityLabel(permissionManager.isAccessibilityGranted
                                                    ? String(localized: "Granted")
                                                    : String(localized: "Access Required"))

                            Button(String(localized: "Open Settings")) {
                                let shouldReset = !permissionManager.isAccessibilityGranted
                                permissionManager.requestAccessibilityPermission(proactivelyResetStaleTCC: shouldReset)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            permissionManager.startMonitoring()
            launchManager.syncStatus()
        }
        .onDisappear { permissionManager.stopMonitoring() }
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
