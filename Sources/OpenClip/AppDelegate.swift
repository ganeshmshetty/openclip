// AppDelegate.swift
// OpenClip
//
// Handles macOS NSApplication lifecycle events, status bar item initialization, onboarding display checks, and hotkey registration.
import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import Core
import SDWebImage
import SDWebImageSVGCoder
@preconcurrency import UserNotifications

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private var selectionMonitor: (any SelectionMonitoring)?
    private var popupController: PopupWindowController?
    private var aiActionSync: AIActionSync?
    private var extensionsWatcher: ExtensionsDirectoryWatcher?

    private var onboardingWindowController: OnboardingWindowController?
    private var permissionRecoveryWindowController: PermissionRecoveryWindowController?
    private var coachMarkController: CoachMarkController?

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusBarController?.showPreferences()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        // Register logging sinks (Rotating File Appender and In-Memory Buffer)
        let rotatingSink = RotatingFileLogSink()
        RotatingFileLogSink.shared = rotatingSink
        Log.addSink(rotatingSink)
        _ = DebugLogStore.shared

        // Remove temporary calendar .ics files a previous session left behind before its
        // deferred cleanup could run (crash or quit during the delay window).
        DefaultActionResultHandler.purgeStaleCalendarTempFiles()

        switch DebugLogCommand.parse(CommandLine.arguments) {
        case .showVersion:
            print(DebugLogCommand.version)
            exit(0)
        case .showHelp:
            print(DebugLogCommand.usage)
            exit(0)
        case .usageError(let message):
            FileHandle.standardError.write(Data("error: \(message)\n\n\(DebugLogCommand.usage)\n".utf8))
            exit(2)
        case .dumpLogs(let options):
            runDumpLogsCommand(options)
            return
        case .none:
            break
        }

        // Register SVG coder
        let svgCoder = SDImageSVGCoder.shared
        SDImageCodersManager.shared.addCoder(svgCoder)

        // Force accessory (agent) mode immediately.
        // LSUIElement=true sets this at launch, but SwiftUI's Settings{} scene can
        // temporarily switch us to .regular. Calling this here ensures we stay
        // invisible in the Dock and App Switcher at all times.
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize the status bar controller
        statusBarController = StatusBarController()
        
        // Setup popup controller
        let controller = PopupWindowController()
        popupController = controller
        
        // Setup global shortcut hotkey manager
        HotkeyManager.shared.setup(popupController: controller)

        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            await ActionCoordinator.shared.loadInitialState(
                dictionaryLookup: DictionaryLookupFactory.systemLookup
            )
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            ActionCoordinator.shared.register(action: CompletionAction())
            // Register each AI preset as an individual action (palette + Preferences → Actions).
            aiActionSync = AIActionSync.shared

            // Watch ~/.openclip/extensions and reload on changes so extensions installed or
            // edited outside the app (store installs, install_extension.sh, manifest edits)
            // appear without relaunching. Started after loadInitialState so the
            // onRegister/onUnregister registry wiring is already in place.
            startExtensionWatcher()
        }
        
        // Setup selection monitor
        let macMonitor = MacSelectionMonitor()
        macMonitor.onSelection = { [weak self] context, canPaste in
            let isEnabled = DefaultSettingsStore.shared.get(.isAppEnabled)
            let isPaused = DefaultSettingsStore.shared.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970
            if isEnabled && !isPaused {
                // A real selection means the user has seen (or no longer needs) the nudge.
                self?.coachMarkController?.dismiss()
                self?.popupController?.show(for: context, pasteAvailable: canPaste)
            }
        }
        macMonitor.preparePasteProbe = { [weak self] app, policy in
            self?.popupController?.preparePasteProbe(for: app, policy: policy)
        }
        selectionMonitor = macMonitor
        guard NSClassFromString("XCTestCase") == nil else { return }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let lastRunVersion = DefaultSettingsStore.shared.get(.lastRunVersion)
        let lastRunBuild = DefaultSettingsStore.shared.get(.lastRunBuild)
        let completedOnboarding = DefaultSettingsStore.shared.get(.hasCompletedOnboarding)
        let isGranted = PermissionManager.shared.isAccessibilityGranted
        let isAppEnabled = DefaultSettingsStore.shared.get(.isAppEnabled)

        let launchScenario = AppLaunchClassifier.classify(
            lastRunVersion: lastRunVersion,
            currentVersion: currentVersion,
            lastRunBuild: lastRunBuild,
            currentBuild: currentBuild,
            hasCompletedOnboarding: completedOnboarding,
            isAccessibilityGranted: isGranted
        )

        switch launchScenario {
        case .firstInstall:
            showOnboarding()
        case .appUpdate(let prevVersion, let newVersion, let prevBuild, let newBuild):
            Log.permissions.info("OpenClip updated from \(prevVersion, privacy: .public) (\(prevBuild, privacy: .public)) to \(newVersion, privacy: .public) (\(newBuild, privacy: .public))")
            DefaultSettingsStore.shared.set(.lastRunVersion, value: newVersion)
            DefaultSettingsStore.shared.set(.lastRunBuild, value: newBuild)
            if !isGranted {
                showPermissionRecovery(isUpdate: true)
            } else {
                if isAppEnabled {
                    selectionMonitor?.start()
                }
                showPostOnboardingCoachMark()
            }
        case .permissionRecovery:
            showPermissionRecovery(isUpdate: false)
        case .normalLaunch:
            if lastRunVersion != currentVersion || lastRunBuild != currentBuild {
                DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
                DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
            }
            if isGranted && isAppEnabled {
                selectionMonitor?.start()
            }
            showPostOnboardingCoachMark()
            Task {
                _ = try? await ExtensionsAPIClient.shared.fetchExtensions()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openClipShowSandboxPopup,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let context = notification.object as? SelectionContext else { return }
            Task { @MainActor in
                self?.popupController?.show(for: context, pasteAvailable: false)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openClipEnabledStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let explicitState = notification.object as? Bool
            Task { @MainActor in
                let enabled = explicitState ?? DefaultSettingsStore.shared.get(.isAppEnabled)
                if enabled {
                    let granted = PermissionManager.shared.isAccessibilityGranted
                    if granted {
                        self?.selectionMonitor?.start()
                    }
                } else {
                    self?.selectionMonitor?.stop()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openClipAccessibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let granted = (notification.object as? Bool) ?? PermissionManager.shared.isAccessibilityGranted
            Task { @MainActor in
                let enabled = DefaultSettingsStore.shared.get(.isAppEnabled)
                if granted && enabled {
                    self?.selectionMonitor?.start()
                } else if !granted {
                    self?.selectionMonitor?.stop()
                }
            }
        }
    }

    private func showOnboarding() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        // Deliberately no post-finish window dump: completing (or skipping) onboarding hands
        // control straight back with a one-time "try it" coach-mark — the user's next step is to
        // select text, not read Preferences.
        popupController?.isOnboardingVisible = true
        onboardingWindowController = OnboardingWindowController { [weak self] in
            self?.popupController?.isOnboardingVisible = false
            if DefaultSettingsStore.shared.get(.isAppEnabled) {
                self?.selectionMonitor?.start()
            }
            self?.showPostOnboardingCoachMark()
        }
        onboardingWindowController?.showWindow(nil)
    }

    private func showPermissionRecovery(isUpdate: Bool) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        permissionRecoveryWindowController = PermissionRecoveryWindowController(
            isUpdate: isUpdate,
            onComplete: { [weak self] in
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
                DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
                if DefaultSettingsStore.shared.get(.isAppEnabled) {
                    self?.selectionMonitor?.start()
                }
                self?.showPostOnboardingCoachMark()
            },
            onDismiss: { [weak self] in
                // Persist version/build even on "Later" so the same prompt isn't re-shown
                // on every launch when the build is already current (idempotent).
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                let lastRunVersion = DefaultSettingsStore.shared.get(.lastRunVersion)
                let lastRunBuild = DefaultSettingsStore.shared.get(.lastRunBuild)
                if lastRunVersion != currentVersion || lastRunBuild != currentBuild {
                    DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
                    DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
                }
                self?.showPostOnboardingCoachMark()
            }
        )
        permissionRecoveryWindowController?.showWindow(nil)
    }

    /// One-time post-onboarding nudge: teaches the primary gesture ("select any text") when
    /// Accessibility is in place, or offers a Preferences shortcut when the user skipped it.
    /// `CoachMarkController` self-guards on its persisted seen-flag, so this is safe to call from
    /// both the onboarding-completion path and subsequent launches until it's been dismissed once.
    private func showPostOnboardingCoachMark() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        let controller = CoachMarkController(
            accessibilityGranted: PermissionManager.shared.isAccessibilityGranted,
            onSetupAction: { [weak self] in
                self?.statusBarController?.showPreferences()
            })
        coachMarkController = controller
        controller.show(anchorFrame: statusBarController?.statusItemButtonFrame)
    }

    /// Starts the extensions-directory watcher so extension changes are hot-reloaded without a relaunch.
    private func startExtensionWatcher() {
        let watcher = ExtensionsDirectoryWatcher {
            await ExtensionManager.shared.loadExtensions(from: Constants.extensionsDirectory)
        }
        watcher.start(watching: Constants.extensionsDirectory)
        extensionsWatcher = watcher
    }

    /// Runs the app in `--dump-logs` mode: runs the normal startup action load
    /// (this is where extension load/rejection lines are logged), fetches matching entries
    /// from the in-memory buffer with 0ms indexing lag, prints them, and exits.
    private func runDumpLogsCommand(_ options: DebugLogCommand.DumpOptions) {
        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            await ActionCoordinator.shared.loadInitialState(
                dictionaryLookup: DictionaryLookupFactory.systemLookup
            )
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            ActionCoordinator.shared.register(action: CompletionAction())
            if options.collectSeconds > 0 {
                try? await Task.sleep(for: .seconds(options.collectSeconds))
            }
            let entries = DebugLogStore.shared.entries(matching: options.filter)
            print("OpenClip log dump (\(entries.count) entr\(entries.count == 1 ? "y" : "ies"))")
            for entry in entries {
                print(DebugLogCommand.formattedLine(entry))
            }
            exit(0)
        }
    }

    public nonisolated static func parseDeepLinkURL(_ url: URL) -> [String: String]? {
        guard url.scheme?.lowercased() == "openclip", url.host == "install" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        
        var dict: [String: String] = [:]
        for item in queryItems {
            if let val = item.value {
                dict[item.name] = val
            }
        }
        return dict
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let params = Self.parseDeepLinkURL(url),
                  let downloadStr = params["url"],
                  let downloadURL = URL(string: downloadStr),
                  let extID = params["id"] else { continue }
            
            guard let host = downloadURL.host?.lowercased(),
                  RemoteExtensionInstaller.allowedDownloadHosts.contains(host) else {
                continue
            }
            
            let alert = NSAlert()
            alert.messageText = String(localized: "Install Extension?")
            alert.informativeText = String(localized: "OpenClip wants to install the extension \"\(extID)\" from \(host). Extensions can run scripts when you select text. Only proceed if you trust this source.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Install"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { continue }
            
            Task { @MainActor in
                do {
                    ExtensionManager.shared.prepareInstall(source: "store", packageID: extID)
                    _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(downloadURL, extensionID: extID)
                    await ExtensionUpdateManager.shared.checkForUpdates()
                } catch {
                    Log.extensions.error("Failed to install extension '\(extID, privacy: .public)' from host \(host, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    let failure = NSAlert()
                    failure.messageText = String(localized: "Extension Install Failed")
                    failure.informativeText = String(localized: "OpenClip could not install \"\(extID)\": \(error.localizedDescription)")
                    failure.alertStyle = .warning
                    failure.runModal()
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["type"] as? String == "app_update" {
            Task { @MainActor in
                AppUpdateManager.shared.checkForUpdates()
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
