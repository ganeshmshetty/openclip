import AppKit
import SwiftUI

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    private var preferencesWindow: NSWindow?
    
    /// Initializes a new status bar controller.
    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Using a standard system image for the clipboard/clip concept
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
        }
        
        setupMenu()
    }
    
    /// Sets up the menu for the status bar item.
    private func setupMenu() {
        let menu = NSMenu()
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc public func showPreferences() {
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: controller)
        window.title = "OpenClip Preferences"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
