import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        requestAccessibilityPermissions()
        
        // Initialize the status bar controller
        statusBarController = StatusBarController()
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
