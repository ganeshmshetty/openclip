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

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var selectionMonitor: (any SelectionMonitoring)?
    private var popupController: PopupWindowController?
    private var aiActionSync: AIActionSync?
    private var extensionsWatcher: ExtensionsDirectoryWatcher?

    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch DebugLogCommand.parse(CommandLine.arguments) {
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

        // DebugLogStore stays stopped in normal app runs: its 1s OSLogStore poll loop keeps
        // OSLogService.xpc burning CPU for the app's whole lifetime. Only --dump-logs starts it
        // (runDumpLogsCommand), where the process exits right after the dump.

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
            let optionStore = KeychainActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            await ActionCoordinator.shared.loadInitialState()
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
            if isEnabled {
                self?.popupController?.show(for: context, pasteAvailable: canPaste)
            }
        }
        macMonitor.preparePasteProbe = { [weak self] app, policy in
            self?.popupController?.preparePasteProbe(for: app, policy: policy)
        }
        selectionMonitor = macMonitor
        
        let isGranted = PermissionManager.shared.isAccessibilityGranted
        let completedOnboarding = DefaultSettingsStore.shared.get(.hasCompletedOnboarding)
        let isAppEnabled = DefaultSettingsStore.shared.get(.isAppEnabled)
        
        if !isGranted || !completedOnboarding {
            showOnboarding()
        } else if isAppEnabled {
            selectionMonitor?.start()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenClipEnabledStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
            if enabled {
                let granted = PermissionManager.shared.isAccessibilityGranted
                let onboarded = DefaultSettingsStore.shared.get(.hasCompletedOnboarding)
                if granted && onboarded {
                    self?.selectionMonitor?.start()
                }
            } else {
                self?.selectionMonitor?.stop()
            }
        }
    }
    
    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController { [weak self] in
            if DefaultSettingsStore.shared.get(.isAppEnabled) {
                self?.selectionMonitor?.start()
            }
            self?.statusBarController?.showPreferences()
        }
        onboardingWindowController?.showWindow(nil)
    }

    /// Starts the extensions-directory watcher so extension changes are hot-reloaded without a relaunch.
    private func startExtensionWatcher() {
        let watcher = ExtensionsDirectoryWatcher {
            await ExtensionManager.shared.loadExtensions(from: Constants.extensionsDirectory)
        }
        watcher.start(watching: Constants.extensionsDirectory)
        extensionsWatcher = watcher
    }

    /// Runs the app in `--dump-logs` mode: start the store, run the normal startup action load
    /// (this is where extension load/rejection lines are logged), wait the collect window, print
    /// the filtered snapshot, and exit.
    private func runDumpLogsCommand(_ options: DebugLogCommand.DumpOptions) {
        DebugLogStore.shared.start()

        Task {
            let optionStore = KeychainActionOptionStore()
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
            ExtensionManager.shared.optionWriter = optionStore
            await ActionCoordinator.shared.loadInitialState()
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            ActionCoordinator.shared.register(action: CompletionAction())
            try? await Task.sleep(for: .seconds(options.collectSeconds))
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
            alert.messageText = "Install Extension?"
            alert.informativeText = "OpenClip wants to install the extension \"\(extID)\" from \(host). Extensions can run scripts when you select text. Only proceed if you trust this source."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { continue }
            
            Task { @MainActor in
                do {
                    _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(downloadURL, extensionID: extID)
                } catch {
                    Log.extensions.error("Failed to install extension '\(extID, privacy: .public)' from host \(host, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    let failure = NSAlert()
                    failure.messageText = "Extension Install Failed"
                    failure.informativeText = "OpenClip could not install \"\(extID)\": \(error.localizedDescription)"
                    failure.alertStyle = .warning
                    failure.runModal()
                }
            }
        }
    }
}
