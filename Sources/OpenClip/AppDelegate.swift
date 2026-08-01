import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import Core

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var selectionMonitor: (any SelectionMonitoring)?
    private var popupController: PopupWindowController?

    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        ActionRegistry.shared.register(builtIns: [
            SearchAction(),
            CopyAction(),
            CutAction(),
            PasteAction(),
            CalculateAction(),
            OpenURLAction(),
            ServicesAction()
        ])
        
        Task {
            await RuleEngine.shared.loadRules(from: Constants.rulesFileURL)
            await ExtensionManager.shared.loadExtensions()
            for action in ExtensionManager.shared.loadedActions {
                ActionRegistry.shared.register(action: action)
            }
        }
        
        // Setup selection monitor
        let retriever = MacTextRetriever()
        let monitor = MacSelectionMonitor(retriever: retriever)
        monitor.onSelection = { [weak self] context in
            self?.popupController?.show(for: context)
        }
        selectionMonitor = monitor
        
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

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: url)
                    await MainActor.run {
                        self.statusBarController?.showPreferences()
                    }
                } catch {
                    print("Failed to install extension from Finder: \(error)")
                }
            }
        }
    }
}
