import AppKit

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    
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
        
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
}
