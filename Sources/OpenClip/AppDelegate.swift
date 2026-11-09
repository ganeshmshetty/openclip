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
    private var captureTextController: CaptureTextController?
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

    func applicationWillTerminate(_ notification: Notification) {
        captureTextController?.cancel()
        ExtensionUpdateManager.shared.stopAutomaticUpdates()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The test host must never grow a Dock icon of its own.
        if NSClassFromString("XCTestCase") != nil { NSApp.setActivationPolicy(.accessory) }
        UNUserNotificationCenter.current().delegate = self

        // Register logging sinks (Rotating File Appender and In-Memory Buffer)
        let rotatingSink = RotatingFileLogSink()
        RotatingFileLogSink.shared = rotatingSink
        Log.addSink(rotatingSink)
        _ = DebugLogStore.shared
        ActionSound.prepareIfEnabled()

        DiagnosticsHub.shared.install(OpenClipDiagnosticsSink())
        DiagnosticsHub.shared.setReportMode(.onFailureOrSlow)

        // Remove temp calendar .ics files left by a previous session (crash or quit before its deferred cleanup).
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

        let svgCoder = SDImageSVGCoder.shared
        SDImageCodersManager.shared.addCoder(svgCoder)

        // Force accessory mode: SwiftUI's Settings{} scene can switch us to .regular, so re-assert it.
        NSApp.setActivationPolicy(.accessory)
        
        statusBarController = StatusBarController()

        setupMainMenu()

        // Deep links can open Preferences; configured before any open(_:) call can arrive.
        DeepLinkRouter.shared.configure { [weak self] in
            self?.statusBarController?.showPreferences()
        }

        LocalExtensionInstaller.shared.configure { [weak self] in
            self?.statusBarController?.showPreferences()
        }
        
        let controller = PopupWindowController()
        popupController = controller
        
        let macMonitor = MacSelectionMonitor()
        controller.selectionIsCurrent = { [weak macMonitor] context in
            guard let generation = context.selectionGeneration else { return true }
            return macMonitor?.selectionGeneration == generation
        }
        // Presentation gate only: Appear Automatically is checked on the passive path, not here, so the hold
        // gesture and ⌥⌘C still summon the popup. Pause is rechecked here since the hold sleeps can outlast it.
        macMonitor.onSelection = { [weak self] context, canPaste in
            let isPaused = DefaultSettingsStore.shared.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970
            if isPaused || self?.popupController == nil {
                Log.selection.debug("[Trace#\(context.traceID ?? 0, privacy: .public)] popup delivery blocked paused=\(isPaused, privacy: .public) controllerAvailable=\(self?.popupController != nil, privacy: .public)")
            }
            if !isPaused {
                // A real selection means the user has seen (or no longer needs) the nudge.
                self?.coachMarkController?.dismiss()
                self?.popupController?.show(for: context, pasteAvailable: canPaste)
            }
        }
        let captureController = CaptureTextController(popupController: controller)
        captureTextController = captureController
        macMonitor.isSuppressed = { [weak self, weak captureController] in
            captureController?.isCapturing == true || self?.popupController?.modeStore.mode == .search
        }
        statusBarController?.onCaptureText = { [weak captureController] sourceApp in
            captureController?.toggleCapture(sourceApp: sourceApp)
        }
        macMonitor.preparePasteProbe = { [weak self] app, policy in
            self?.popupController?.preparePasteProbe(for: app, policy: policy)
        }
        // Don't re-open the action bar over a dragged-aside result card from the same source app.
        macMonitor.isSuppressedForApp = { [weak self] bundleID in
            guard let self, let popup = self.popupController, popup.cardIsModal,
                  let source = popup.sourceAppBundleID, let bundleID else { return false }
            return bundleID == source
        }
        selectionMonitor = macMonitor

        HotkeyManager.shared.setup(popupController: controller, selectionMonitor: macMonitor, captureTextController: captureController)

        let optionStore = SecretActionOptionStore()
        ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore, isSelectionCurrent: { [weak self] selection in
            self?.popupController?.selectionIsCurrent(selection) == true
        })
        ExtensionManager.shared.optionWriter = optionStore
        ExtensionManager.shared.optionReader = optionStore
        ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
        ExtensionManager.shared.onReloaded = { VisibilityPredicateRuntime.shared.invalidate() }
        CustomActionJSRunnerRegistry.runner = DefaultCustomActionJSRunner()

        Task {
            await ActionCoordinator.shared.loadInitialState(
                dictionaryLookup: DictionaryLookupFactory.systemLookup
            )
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            ActionCoordinator.shared.register(action: CompletionAction())
            ActionCoordinator.shared.register(action: AIToolsAction())
            // Register each AI preset as an individual action (palette + Preferences → Actions).
            aiActionSync = AIActionSync.shared

            // Watch ~/.openclip/extensions so outside edits hot-reload; started after loadInitialState so
            // the registry callbacks are already wired.
            startExtensionWatcher()
            if NSClassFromString("XCTestCase") == nil {
                ExtensionUpdateManager.shared.startAutomaticUpdates()
            }
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
            // Appear Automatically is evaluated by the selection monitor, which keeps running for the hold gesture and ⌥⌘C.
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
        // No post-finish dump: onboarding hands back with a one-time coach mark, so the next step is selecting text.
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
                // Persist version/build even on Later so the prompt is not re-shown on every launch.
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

    /// One-time nudge after onboarding. `CoachMarkController` guards on its seen-flag, so calling it each launch is safe.
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

    @objc private func openPreferencesMenuItemAction() {
        statusBarController?.showPreferences()
    }

    /// Standard main menu. Agent apps need it so AppKit routes ⌘V/⌘C/⌘X/⌘A/⌘Z/⌘W to the first responder.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: String(localized: "About OpenClip"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openPreferencesMenuItemAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: String(localized: "Hide OpenClip"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: String(localized: "Quit OpenClip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenuItem.submenu = editMenu

        let undoItem = NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        let cutItem = NSMenuItem(title: String(localized: "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(cutItem)
        let copyItem = NSMenuItem(title: String(localized: "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(copyItem)
        let pasteItem = NSMenuItem(title: String(localized: "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(pasteItem)
        let pasteMatchStyleItem = NSMenuItem(title: String(localized: "Paste and Match Style"), action: Selector(("pasteAsPlainText:")), keyEquivalent: "V")
        pasteMatchStyleItem.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatchStyleItem)
        let deleteItem = NSMenuItem(title: String(localized: "Delete"), action: Selector(("delete:")), keyEquivalent: "")
        editMenu.addItem(deleteItem)
        let selectAllItem = NSMenuItem(title: String(localized: "Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editMenu.addItem(selectAllItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenuItem.submenu = windowMenu
        let closeItem = NSMenuItem(title: String(localized: "Close Window"), action: Selector(("performClose:")), keyEquivalent: "w")
        windowMenu.addItem(closeItem)
        let minimizeItem = NSMenuItem(title: String(localized: "Minimize"), action: Selector(("performMiniaturize:")), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)
        let zoomItem = NSMenuItem(title: String(localized: "Zoom"), action: Selector(("performZoom:")), keyEquivalent: "")
        windowMenu.addItem(zoomItem)
        windowMenu.addItem(NSMenuItem.separator())
        let frontItem = NSMenuItem(title: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(frontItem)

        NSApp.mainMenu = mainMenu
    }

    /// Starts the extensions-directory watcher so extension changes are hot-reloaded without a relaunch.
    private func startExtensionWatcher() {
        let watcher = ExtensionsDirectoryWatcher {
            await ExtensionManager.shared.loadExtensions(from: Constants.extensionsDirectory)
        }
        watcher.start(watching: Constants.extensionsDirectory)
        extensionsWatcher = watcher
    }

    /// `--dump-logs` mode: runs startup loads (so extension load lines get logged), prints matching buffer entries, exits.
    private func runDumpLogsCommand(_ options: DebugLogCommand.DumpOptions) {
        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore, isSelectionCurrent: { [weak self] selection in
                self?.popupController?.selectionIsCurrent(selection) == true
            })
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.optionReader = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            ExtensionManager.shared.onReloaded = { VisibilityPredicateRuntime.shared.invalidate() }
            CustomActionJSRunnerRegistry.runner = DefaultCustomActionJSRunner()
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

    /// `--dump-settings` mode: loads startup state, prints a JSON snapshot of every setting, and exits.
    private func runDumpSettingsCommand() {
        Task {
            let optionStore = SecretActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore, isSelectionCurrent: { [weak self] selection in
                self?.popupController?.selectionIsCurrent(selection) == true
            })
            ExtensionManager.shared.optionWriter = optionStore
            ExtensionManager.shared.optionReader = optionStore
            ExtensionManager.shared.settingsStore = DefaultSettingsStore.shared
            ExtensionManager.shared.onReloaded = { VisibilityPredicateRuntime.shared.invalidate() }
            CustomActionJSRunnerRegistry.runner = DefaultCustomActionJSRunner()
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

    /// Install-only parameter extraction for the store deep-link tests; new code uses `OpenClipDeepLink`.
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
            if LocalExtensionInstaller.isExtensionPackageURL(url) {
                Task { @MainActor in
                    await LocalExtensionInstaller.shared.install(from: url)
                }
                continue
            }
            DeepLinkRouter.shared.handle(url)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        application(sender, open: urls)
        sender.reply(toOpenOrPrint: .success)
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
