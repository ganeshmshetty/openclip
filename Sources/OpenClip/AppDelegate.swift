import AppKit
@preconcurrency import ApplicationServices
import SwiftUI
import Core

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var selectionCoordinator: SelectionCoordinator?
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
        
        Task {
            await ActionCoordinator.shared.loadInitialState()
            ActionCoordinator.shared.register(action: CompletionAction())
            ActionCoordinator.shared.register(action: OpenURLAction())
            ActionCoordinator.shared.register(action: ServicesAction())
            ActionCoordinator.shared.register(action: AirDropAction())
        }
        
        // Setup selection coordinator
        let retriever = MacTextRetriever()
        let macMonitor = MacSelectionMonitor(retriever: retriever)
        let coordinator = SelectionCoordinator(monitor: macMonitor)
        coordinator.onSelection = { [weak self] context in
            self?.popupController?.show(for: context)
        }
        selectionCoordinator = coordinator
        
        let isGranted = PermissionManager.shared.isAccessibilityGranted
        let completedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !isGranted || !completedOnboarding {
            showOnboarding()
        } else {
            selectionCoordinator?.start()
        }
    }
    
    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController { [weak self] in
            self?.selectionCoordinator?.start()
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
