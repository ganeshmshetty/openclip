import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

/// Manages the application lifecycle and permissions.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the app as an accessory to hide the dock icon (equivalent to LSUIElement)
        NSApp.setActivationPolicy(.accessory)
        
        // Request accessibility permissions
        requestAccessibilityPermissions()
        
        // Initialize the status bar controller
        statusBarController = StatusBarController()
    }
    
    /// Requests Accessibility permissions on first launch.
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if !isTrusted {
            print("Accessibility permission is missing. Please grant it in System Settings.")
            // Graceful degradation: The app won't crash, but won't be able to read global shortcuts properly without it.
        }
    }
}
