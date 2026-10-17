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
    @Setting(SettingKey.captureTextAutoCopy) private var captureTextAutoCopy
    @Setting(SettingKey.playCopySound) private var playCopySound
    @Setting(SettingKey.copySoundName) private var copySoundName
    @State private var fileSaveLocation: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var highlightedControlID: String?

    /// Initializes preference state from the shared settings store.
    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _showMenuBarIcon = State(initialValue: DefaultSettingsStore.shared.get(.showMenuBarIcon))
        _isMouseHoldEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isMouseHoldEnabled))
        _fileSaveLocation = State(initialValue: DefaultSettingsStore.shared.get(.fileSaveLocation))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                // Everything that decides how the popup and palette are summoned
                SettingsCard("Selection & Mouse") {
                    SettingsToggleRow(
                        title: "Appear Automatically",
                        info: "Show the popup as soon as text is selected.",
                        systemImage: "cursorarrow",
                        plainIcon: true,
                        isOn: $isAppEnabled
                    )
                    .id(GeneralSearchTarget.appearAutomatically)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.appearAutomatically))
                    .onChange(of: isAppEnabled) { _, newValue in
                        DefaultSettingsStore.shared.set(.isAppEnabled, value: newValue)
                        NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Hold Mouse to Trigger",
                        info: "Press and hold without moving the mouse to summon the popup.",
                        systemImage: "hand.tap",
                        plainIcon: true,
                        isOn: $isMouseHoldEnabled
                    )
                    .id(GeneralSearchTarget.holdMouseToTrigger)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.holdMouseToTrigger))
                    .onChange(of: isMouseHoldEnabled) { _, newValue in
                        DefaultSettingsStore.shared.set(.isMouseHoldEnabled, value: newValue)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenClipEnabledStateChanged"))) { notification in
                    isAppEnabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
                }

                SettingsCard("Shortcuts") {
                    SettingsRow(
                        title: "Command Palette",
                        info: "Open the search palette for selected text or clipboard.",
                        systemImage: "command",
                        plainIcon: true
                    ) {
                        Shortcut(for: .togglePopup)
                    }
                    .id(GeneralSearchTarget.commandPalette)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.commandPalette))

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsRow(
                            title: "Capture Text",
                            info: "Select a screen region to extract text.",
                            systemImage: "viewfinder",
                            plainIcon: true
                        ) {
                            Shortcut(for: .captureText)
                        }
                        .id(GeneralSearchTarget.captureText)
                        .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.captureText))

                        Toggle("Copy to Clipboard Automatically", isOn: $captureTextAutoCopy)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesignTokens.secondaryText)
                            .help(String(localized: "The action popup still opens after capture."))
                            .padding(.leading, SettingsDesignTokens.dividerInsetLeading + 4)
                            .padding(.trailing, SettingsDesignTokens.sectionCardPaddingH)
                            .padding(.bottom, SettingsDesignTokens.sectionCardPaddingV)
                            .id(GeneralSearchTarget.captureTextAutoCopy)
                            .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.captureTextAutoCopy))
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
                    .id(GeneralSearchTarget.saveLocation)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.saveLocation))
                }

                SettingsCard("App") {
                    SettingsRow(
                        title: "Play Sound on Copy",
                        systemImage: "speaker.wave.2",
                        plainIcon: true
                    ) {
                        HStack(spacing: 10) {
                            Picker("Sound", selection: $copySoundName) {
                                ForEach(CopySound.allCases) { sound in
                                    Text(LocalizedStringKey(sound.title)).tag(sound.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                            .disabled(!playCopySound)
                            .onChange(of: copySoundName) { _, newValue in
                                CopySound(stored: newValue).play()
                            }

                            Toggle("", isOn: $playCopySound)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Play Sound on Copy")
                        }
                    }
                    .id(GeneralSearchTarget.playCopySound)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.playCopySound))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Show Menu Bar Icon",
                        systemImage: "menubar.rectangle",
                        plainIcon: true,
                        isOn: $showMenuBarIcon
                    )
                    .id(GeneralSearchTarget.showMenuBarIcon)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.showMenuBarIcon))
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
                    .id(GeneralSearchTarget.startAtLogin)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.startAtLogin))

                    if launchManager.requiresApproval {
                        SettingsDivider()
                        SettingsRow(
                            title: "Approval Required",
                            info: "Enable OpenClip under System Settings > General > Login Items & Extensions.",
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
                        info: "Required to read the selected text.",
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
                                permissionManager.requestAccessibilityPermission()
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
                    .id(GeneralSearchTarget.accessibilityAccess)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.accessibilityAccess))

                    SettingsDivider()

                    SettingsRow(
                        title: "Screen Recording Access",
                        info: "Required for Capture Text. Restart OpenClip after allowing it.",
                        systemImage: "rectangle.dashed.badge.record",
                        plainIcon: true
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: permissionManager.isScreenRecordingGranted
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(permissionManager.isScreenRecordingGranted ? Color.green : Color.orange)
                                .accessibilityLabel(permissionManager.isScreenRecordingGranted
                                                    ? String(localized: "Granted")
                                                    : String(localized: "Access Required"))

                            Button(String(localized: "Open Settings")) {
                                permissionManager.requestScreenRecordingPermission()
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
                    .id(GeneralSearchTarget.screenRecordingAccess)
                    .modifier(GeneralSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.screenRecordingAccess))
                }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .task(id: router.generalRevealRequest?.id) {
                guard let request = router.generalRevealRequest else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(request.targetID, anchor: .center)
                }
                highlightedControlID = request.targetID
                do {
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    if router.generalRevealRequest?.id == request.id {
                        highlightedControlID = nil
                        router.clearGeneralRevealRequest(request.id)
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                highlightedControlID = nil
                router.clearGeneralRevealRequest(request.id)
            }
            .onAppear {
                permissionManager.startMonitoring()
                launchManager.syncStatus()
            }
            .onDisappear { permissionManager.stopMonitoring() }
        }
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

private struct GeneralSearchHighlight: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1)
                        }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isHighlighted)
    }
}
