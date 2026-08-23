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

        menu.addItem(menuItem(title: "Preferences", action: #selector(showPreferences),
                              keyEquivalent: ",", symbol: "gearshape"))

        menu.addItem(menuItem(title: "Report an Issue", action: #selector(openReportIssue),
                              symbol: "exclamationmark.bubble"))

        menu.addItem(menuItem(title: "Check for Updates", action: #selector(checkForUpdates),
                              symbol: "arrow.triangle.2.circlepath"))

        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    /// Builds a menu item with an SF Symbol glyph in its leading image slot, targeted at self
    /// (status-item menus don't resolve actions through the responder chain). Missing symbols
    /// degrade to a text-only item.
    private func menuItem(title: String, action: Selector, keyEquivalent: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            image.isTemplate = true
            item.image = image
        }
        return item
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

    /// Screen frame of the status item's button, for anchoring surfaces (e.g. the post-onboarding
    /// coach mark) below it. Nil until the button has joined a window.
    var statusItemButtonFrame: NSRect? {
        statusItem.button?.window?.frame
    }
    
    private func updateStatusIcon(isEnabled: Bool) {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            button.alphaValue = isEnabled ? 1.0 : 0.45
            // The enabled state must be legible beyond the purely visual alpha dimming.
            button.setAccessibilityLabel("OpenClip")
            button.setAccessibilityValue(isEnabled ? "Appear Automatically is on" : "Appear Automatically is off")
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
