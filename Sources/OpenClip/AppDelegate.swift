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
    private var decisionActionSync: DecisionActionSync?
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

        OpenSelection.logger = { message in
            Log.selection.debug("\(message, privacy: .public)")
        }

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
        case .dumpSettings:
            runDumpSettingsCommand()
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

        // Deep links can open Preferences (the `open-settings` command); the router is otherwise
        // self-contained. Configured before any `application(_:open:)` call can arrive.
        DeepLinkRouter.shared.configure { [weak self] in
            self?.statusBarController?.showPreferences()
        }
        
        // Setup popup controller
        let controller = PopupWindowController()
        popupController = controller
        
        // Setup selection monitor
        let macMonitor = MacSelectionMonitor()
        // Presentation gate only: "Appear Automatically" is evaluated by the monitor on its
        // passive (mouse-release/keyboard) path, not here — the explicit hold gesture and the
        // ⌥⌘C hotkey must still summon the popup with it off. Global Pause is rechecked at
        // delivery time here because the hold/retrieval sleeps can outlast the pause toggle.
        macMonitor.onSelection = { [weak self] context, canPaste in
            let isPaused = DefaultSettingsStore.shared.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970
            if !isPaused {
                // A real selection means the user has seen (or no longer needs) the nudge.
                self?.coachMarkController?.dismiss()
                self?.popupController?.show(for: context, pasteAvailable: canPaste)
            }
        }
        macMonitor.preparePasteProbe = { [weak self] app, policy in
            self?.popupController?.preparePasteProbe(for: app, policy: policy)
        }
        // When a user has dragged a result card aside, selecting text in that same source app
        // should not re-open the action bar over the card being viewed. Other apps remain unsuppressed.
        macMonitor.isSuppressedForApp = { [weak self] bundleID in
            guard let self, let popup = self.popupController, popup.cardIsModal,
                  let source = popup.sourceAppBundleID, let bundleID else { return false }
            return bundleID == source
        }
        selectionMonitor = macMonitor

        // Setup global shortcut hotkey manager
        HotkeyManager.shared.setup(popupController: controller, selectionMonitor: macMonitor)

        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.optionReader = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            await ActionCoordinator.shared.loadInitialState(
                dictionaryLookup: DictionaryLookupFactory.systemLookup
            )
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            ActionCoordinator.shared.register(action: CompletionAction())
            // Register each AI preset as an individual action (palette + Preferences → Actions).
            aiActionSync = AIActionSync.shared
            decisionActionSync = DecisionActionSync.shared
            // Quick Assist follows the Live assist setting, including a timed window that
            // survived a relaunch.
            QuickAssistController.shared.syncWithSettings()

            // Watch ~/.openclip/extensions and reload on changes so extensions installed or
            // edited outside the app (store installs, install_extension.sh, manifest edits)
            // appear without relaunching. Started after loadInitialState so the
            // onRegister/onUnregister registry wiring is already in place.
            startExtensionWatcher()
        }
        
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
                selectionMonitor?.start()
                showPostOnboardingCoachMark()
            }
        case .permissionRecovery:
            showPermissionRecovery(isUpdate: false)
        case .normalLaunch:
            if lastRunVersion != currentVersion || lastRunBuild != currentBuild {
                DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
                DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
            }
            if isGranted {
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
        ) { _ in
            // "Appear Automatically" is evaluated by the selection monitor on its passive
            // (mouse-release/keyboard) path. The selection monitor remains running so the
            // explicit hold gesture and hotkeys (⌥⌘C) have immediate access to the selection.
        }

        NotificationCenter.default.addObserver(
            forName: .openClipAccessibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let granted = (notification.object as? Bool) ?? PermissionManager.shared.isAccessibilityGranted
            Task { @MainActor in
                if granted {
                    self?.selectionMonitor?.start()
                } else {
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
            if PermissionManager.shared.isAccessibilityGranted {
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
                if PermissionManager.shared.isAccessibilityGranted {
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
            ExtensionManager.shared.optionReader = optionStore
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

    /// Runs the app in `--dump-settings` mode: loads the normal startup state (so extension and
    /// per-action hotkeys are known), captures a JSON snapshot of every known setting, prints it,
    /// and exits.
    private func runDumpSettingsCommand() {
        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.optionReader = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            await ActionCoordinator.shared.loadInitialState(
                dictionaryLookup: DictionaryLookupFactory.systemLookup
            )
            let actionIDs = ActionCoordinator.shared.actions
                .filter { ActionIdentity.isBindable($0) }
                .map(\.id)
            let snapshot = SettingsSnapshotter.capture(
                store: DefaultSettingsStore.shared,
                keys: SettingsCatalog.all(actionIDs: actionIDs),
                appVersion: DebugLogCommand.version
            )
            if let data = try? snapshot.encoded(), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            exit(0)
        }
    }

    /// Install-only parameter extraction, kept for the existing store deep-link tests. New code
    /// parses through `OpenClipDeepLink`; `DeepLinkRouter` owns the actual handling.
    public nonisolated static func parseDeepLinkURL(_ url: URL) -> [String: String]? {
        guard case .install(let id, let name, let downloadURL) = OpenClipDeepLink.parse(url) else {
            return nil
        }
        var dict: [String: String] = ["id": id, "url": downloadURL.absoluteString]
        if let name { dict["name"] = name }
        return dict
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkRouter.shared.handle(url)
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
