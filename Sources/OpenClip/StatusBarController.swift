// StatusBarController.swift
// OpenClip
//
// Manages the menu bar status item, dropdown menu actions, and preferences window presentation for OpenClip.
import AppKit
import SwiftUI
import Core

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem
    private var preferencesWindow: NSWindow?
    private var toggleEnabledItem: NSMenuItem?
    
    /// Initializes a new status bar controller.
    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChanged(_:)),
            name: Notification.Name("OpenClipEnabledStateChanged"),
            object: nil
        )
    }
    
    /// Sets up the menu for the status bar item.
    private func setupMenu() {
        let menu = NSMenu()
        
        let isEnabled = UserDefaults.standard.object(forKey: Constants.isAppEnabledKey) as? Bool ?? true
        let toggleItem = NSMenuItem(
            title: isEnabled ? "Disable OpenClip" : "Enable OpenClip",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.toggleEnabledItem = toggleItem
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    @objc private func toggleEnabled() {
        let current = UserDefaults.standard.object(forKey: Constants.isAppEnabledKey) as? Bool ?? true
        let newStatus = !current
        UserDefaults.standard.set(newStatus, forKey: Constants.isAppEnabledKey)
        updateStatusItem(isEnabled: newStatus)
        NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newStatus)
    }
    
    @objc private func handleStateChanged(_ notification: Notification) {
        let isEnabled = (notification.object as? Bool) ?? (UserDefaults.standard.object(forKey: Constants.isAppEnabledKey) as? Bool ?? true)
        updateStatusItem(isEnabled: isEnabled)
    }
    
    public func updateStatusItem(isEnabled: Bool) {
        toggleEnabledItem?.title = isEnabled ? "Disable OpenClip" : "Enable OpenClip"
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    private func updateStatusIcon(isEnabled: Bool) {
        if let button = statusItem.button {
            let symbolName = isEnabled ? "paperclip" : "paperclip.badge.ellipsis"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            button.alphaValue = isEnabled ? 1.0 : 0.45
        }
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
        window.setContentSize(NSSize(width: 860, height: 720))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
