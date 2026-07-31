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
        // Initialize the status bar controller
        statusBarController = StatusBarController()
        
        // Setup popup controller
        popupController = PopupWindowController()
        
        ActionRegistry.shared.register(builtIns: [
            CopyAction(),
            CutAction(),
            PasteAction(),
            SearchAction(),
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
        }
        onboardingWindowController?.showWindow(nil)
    }
}
