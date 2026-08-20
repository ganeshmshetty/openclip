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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenConfiguration(_:)),
            name: .openClipOpenActionConfiguration,
            object: nil
        )
    }
    
    /// Sets up the menu for the status bar item.
    private func setupMenu() {
        let menu = NSMenu()
        
        let isEnabled = DefaultSettingsStore.shared.get(.isAppEnabled)
        let toggleItem = NSMenuItem(
            title: "Appear Automatically",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)
        self.toggleEnabledItem = toggleItem
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let reportItem = NSMenuItem(title: "Report an Issue", action: #selector(openReportIssue), keyEquivalent: "")
        reportItem.target = self
        menu.addItem(reportItem)

        let updateItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    @objc private func toggleEnabled() {
        let current = DefaultSettingsStore.shared.get(.isAppEnabled)
        let newStatus = !current
        DefaultSettingsStore.shared.set(.isAppEnabled, value: newStatus)
        updateStatusItem(isEnabled: newStatus)
        NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newStatus)
    }
    
    @objc private func handleStateChanged(_ notification: Notification) {
        let isEnabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
        updateStatusItem(isEnabled: isEnabled)
    }

    @objc private func openReportIssue() {
        if let url = URL(string: "https://github.com/ganeshmshetty/openclip/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkForUpdates() {
        AppUpdateManager.shared.checkForUpdates()
    }
    
    /// Decision 8 config-open path: an action requested its configuration. The popup has already
    /// hidden; open Preferences and hand the request to the coordinator so PreferencesView can
    /// present the matching EditActionSheet (the window may not have existed yet).
    @objc private func handleOpenConfiguration(_ notification: Notification) {
        showPreferences()
    }
    
    public func updateStatusItem(isEnabled: Bool) {
        toggleEnabledItem?.state = isEnabled ? .on : .off
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    private func updateStatusIcon(isEnabled: Bool) {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
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
        window.setContentSize(NSSize(width: 760, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
