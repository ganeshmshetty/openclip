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

    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: KeychainActionOptionStore())
            await ActionCoordinator.shared.loadInitialState()
            ActionCoordinator.shared.register(action: CompletionAction())
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: ServicesAction())
            ActionCoordinator.shared.register(action: RevealInFinderAction())
            // Register each AI preset as an individual action (palette + Preferences → Actions).
            aiActionSync = AIActionSync.shared
        }
        
        // Setup selection monitor
        let retriever = MacTextRetriever()
        let macMonitor = MacSelectionMonitor(retriever: retriever)
        macMonitor.onSelection = { [weak self] context in
            let isEnabled = DefaultSettingsStore.shared.get(.isAppEnabled)
            if isEnabled {
                self?.popupController?.show(for: context)
            }
        }
        selectionMonitor = macMonitor
        
        let isGranted = PermissionManager.shared.isAccessibilityGranted
        let completedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !isGranted || !completedOnboarding {
            showOnboarding()
        } else {
            selectionMonitor?.start()
        }
    }
    
    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController { [weak self] in
            self?.selectionMonitor?.start()
            self?.statusBarController?.showPreferences()
        }
        onboardingWindowController?.showWindow(nil)
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
                _ = try? await RemoteExtensionInstaller.shared.installFromRemoteURL(downloadURL, extensionID: extID)
            }
        }
    }
}
