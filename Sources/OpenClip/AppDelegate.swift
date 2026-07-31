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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        requestAccessibilityPermissions()
        
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
        selectionMonitor?.start()
    }
    
    /// Requests Accessibility permissions on first launch.
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if !isTrusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "OpenClip requires Accessibility permissions to read global keyboard shortcuts. Please grant this permission in System Settings when prompted."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Quit")
            
            // NSAlert must be presented so it becomes visible even if app is LSUIElement
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                let promptOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                AXIsProcessTrustedWithOptions(promptOptions)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
