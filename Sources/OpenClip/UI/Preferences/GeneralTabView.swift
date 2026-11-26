// GeneralTabView.swift
// OpenClip
//
// The General preferences tab: app enable and menu bar toggles, trigger hotkey,
// start-at-login, and system-permission status.
//
// Styled with inset SettingsCards (outside headers, rounded cards, inset hairline dividers).

import SwiftUI
import UniformTypeIdentifiers
import Core
import KeyboardShortcuts

@MainActor
struct GeneralTab: View {
    /// Backed by the settings store — the single owner of `isAppEnabled`.
    @State private var isAppEnabled: Bool
    @State private var showMenuBarIcon: Bool
    @State private var isMouseHoldEnabled: Bool
    @Setting(SettingKey.captureTextAutoCopy) private var captureTextAutoCopy
    @Setting(SettingKey.showSearchAllActions) private var showSearchAllActions
    @Setting(SettingKey.playActionSound) private var playActionSound
    @Setting(SettingKey.actionSoundName) private var actionSoundName
    @State private var fileSaveLocation: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var highlightedControlID: String?
    @Setting(SettingKey.actionSoundCustomName) private var actionSoundCustomName
    @State private var isShowingSoundActions = false
    @State private var soundImportError: String?
    private static let chooseSoundTag = "__choose-file__"

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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.appearAutomatically))
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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.holdMouseToTrigger))
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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.commandPalette))

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
                        .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.captureText))

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
                            .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.captureTextAutoCopy))
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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.saveLocation))
                }

                SettingsCard("App") {
                    SettingsRow(
                        title: "Play Sound",
                        info: "Plays when an action finishes. Use the slider button to choose which actions.",
                        systemImage: "speaker.wave.2",
                        plainIcon: true
                    ) {
                        HStack(spacing: 10) {
                            Picker("Sound", selection: Binding(get: { ActionSound(stored: actionSoundName).rawValue }, set: { $0 == Self.chooseSoundTag ? chooseSoundFile() : (actionSoundName = $0) })) {
                                ForEach(ActionSound.builtIn) { sound in
                                    Text(LocalizedStringKey(sound.title)).tag(sound.rawValue)
                                }
                                if ActionSound(stored: actionSoundName) == .custom || !actionSoundCustomName.isEmpty, CustomActionSound.storedURL() != nil {
                                    Divider()
                                    Text(actionSoundCustomName.isEmpty ? String(localized: "Custom") : actionSoundCustomName)
                                        .tag(ActionSound.custom.rawValue)
                                }
                                Divider()
                                Text("Choose File…").tag(Self.chooseSoundTag)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                            .disabled(!playActionSound)
                            .alert("Can't use this sound", isPresented: Binding(get: { soundImportError != nil }, set: { if !$0 { soundImportError = nil } })) {
                                Button("OK", role: .cancel) {}
                            } message: {
                                Text(soundImportError ?? "")
                            }
                            .onChange(of: actionSoundName) { _, newValue in
                                ActionSound(stored: newValue).play()
                            }
                            .onChange(of: playActionSound) { _, isOn in
                                if isOn { ActionSound.prepareIfEnabled() }
                            }

                            Button {
                                isShowingSoundActions.toggle()
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(playActionSound ? SettingsDesignTokens.primaryText : SettingsDesignTokens.tertiaryText)
                                    .frame(width: 24, height: 24)
                                    .settingsGlassCircle()
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!playActionSound)
                            .help(String(localized: "Choose actions that play the sound"))
                            .popover(isPresented: $isShowingSoundActions, arrowEdge: .top) {
                                ActionSoundPopoverView()
                            }

                            Toggle("", isOn: $playActionSound)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityLabel("Play Sound")
                        }
                    }
                    .id(GeneralSearchTarget.playActionSound)
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.playActionSound))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Show Menu Bar Icon",
                        systemImage: "menubar.rectangle",
                        plainIcon: true,
                        isOn: $showMenuBarIcon
                    )
                    .id(GeneralSearchTarget.showMenuBarIcon)
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.showMenuBarIcon))
                    .onChange(of: showMenuBarIcon) { _, newValue in
                        DefaultSettingsStore.shared.set(.showMenuBarIcon, value: newValue)
                        NotificationCenter.default.post(
                            name: .openClipMenuBarVisibilityChanged,
                            object: newValue
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Show Command Palette",
                        info: "Show the command palette icon at the end of the popup bar. The keyboard shortcut still works when hidden.",
                        systemImage: "magnifyingglass",
                        plainIcon: true,
                        isOn: $showSearchAllActions
                    )
                    .id(GeneralSearchTarget.showCommandPalette)
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.showCommandPalette))

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Start at Login",
                        systemImage: "arrow.clockwise.circle",
                        plainIcon: true,
                        isOn: $launchManager.isEnabled
                    )
                    .id(GeneralSearchTarget.startAtLogin)
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.startAtLogin))

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
                        title: PermissionCopy.accessTitle,
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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.accessibilityAccess))

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
                    .modifier(SettingsSearchHighlight(isHighlighted: highlightedControlID == GeneralSearchTarget.screenRecordingAccess))
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

    /// Lets the user pick their own sound file and makes it the action sound.
    private func chooseSoundFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a short sound (up to 5 seconds)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try CustomActionSound.importFile(from: url)
            ActionSound.evict(.custom)
            actionSoundCustomName = name
            actionSoundName = ActionSound.custom.rawValue
            ActionSound.custom.play()
        } catch let error as CustomActionSound.ImportError {
            soundImportError = error.message
        } catch {
            soundImportError = error.localizedDescription
        }
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
