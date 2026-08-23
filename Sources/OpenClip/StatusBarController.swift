// StatusBarController.swift
// OpenClip
//
// Manages the menu bar status item, dropdown menu actions, and preferences window presentation for OpenClip.
// Formatted according to native macOS status menu conventions with consistent text alignment,
// clean sectional dividers, and standard keyboard shortcuts.
import AppKit
import SwiftUI
import Core

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var preferencesWindow: NSWindow?
    private var toggleEnabledItem: NSMenuItem?
    private var extensionsSubmenu: NSMenu?
    
    /// Initializes a new status bar controller.
    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupMenu()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChanged(_:)),
            name: .openClipEnabledStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenConfiguration(_:)),
            name: .openClipOpenActionConfiguration,
            object: nil
        )
    }
    
    /// Sets up the menu for the status bar item following standard macOS menu hierarchy.
    private func setupMenu() {
        let menu = NSMenu()
        
        // Section 1: Core State Toggle
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

        // Section 2: Core App Navigation
        menu.addItem(menuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))

        let extensionsMenu = NSMenu(title: "Extensions")
        extensionsMenu.delegate = self
        self.extensionsSubmenu = extensionsMenu
        
        let extensionsItem = NSMenuItem(title: "Extensions", action: nil, keyEquivalent: "")
        extensionsItem.submenu = extensionsMenu
        menu.addItem(extensionsItem)
        
        menu.addItem(NSMenuItem.separator())

        // Section 3: Updates & Support
        menu.addItem(menuItem(title: "Check for Updates…", action: #selector(checkForUpdates)))
        menu.addItem(menuItem(title: "Report an Issue…", action: #selector(openReportIssue)))

        menu.addItem(NSMenuItem.separator())
        
        // Section 4: Lifecycle
        let quitItem = NSMenuItem(title: "Quit OpenClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateStatusIcon(isEnabled: isEnabled)
    }
    
    /// Builds a menu item targeted at self (status-item menus don't resolve actions through the responder chain).
    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        let current = DefaultSettingsStore.shared.get(.isAppEnabled)
        let newStatus = !current
        DefaultSettingsStore.shared.set(.isAppEnabled, value: newStatus)
        updateStatusItem(isEnabled: newStatus)
        NotificationCenter.default.post(name: .openClipEnabledStateChanged, object: newStatus)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === extensionsSubmenu else { return }
        menu.removeAllItems()

        // Top pinned action: immediately accessible with zero scrolling
        let manageItem = NSMenuItem(
            title: "Manage Extensions…",
            action: #selector(openActionsTab),
            keyEquivalent: ""
        )
        manageItem.target = self
        menu.addItem(manageItem)

        menu.addItem(NSMenuItem.separator())

        let actions = ActionCoordinator.shared.actions
        let disabledPackages = DefaultSettingsStore.shared.get(.disabledPackages)
        let packages = ExtensionPackageResolver.resolvePackages(from: actions, disabledPackages: disabledPackages)

        if packages.isEmpty {
            let emptyItem = NSMenuItem(title: "No Extensions Installed", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for package in packages {
            let item = NSMenuItem(
                title: package.displayName,
                action: #selector(toggleExtensionPackage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = package.id
            item.state = package.isEnabled ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func openActionsTab() {
        showPreferences(tab: .actions)
    }

    @objc private func toggleExtensionPackage(_ sender: NSMenuItem) {
        guard let packageID = sender.representedObject as? String else { return }
        var disabledPackages = DefaultSettingsStore.shared.get(.disabledPackages)
        let isCurrentlyDisabled = disabledPackages.contains(packageID)

        if isCurrentlyDisabled {
            disabledPackages.remove(packageID)
            DefaultSettingsStore.shared.set(.disabledPackages, value: disabledPackages)
            sender.state = .on
            Task { @MainActor in
                await ExtensionManager.shared.enablePackage(packageID: packageID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
            }
        } else {
            disabledPackages.insert(packageID)
            DefaultSettingsStore.shared.set(.disabledPackages, value: disabledPackages)
            sender.state = .off
            Task { @MainActor in
                await ExtensionManager.shared.disablePackage(packageID: packageID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
            }
        }
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
        showPreferences(tab: .general)
    }

    public func showPreferences(tab: PreferenceTab = .general) {
        if let window = preferencesWindow, window.isVisible {
            NotificationCenter.default.post(name: .openClipSelectPreferencesTab, object: tab)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: PreferencesView(initialTab: tab))
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
