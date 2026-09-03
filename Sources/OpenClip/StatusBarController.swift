// StatusBarController.swift
// OpenClip
//
// Manages the menu bar status item, dropdown menu actions, and preferences window presentation for OpenClip.
// Formatted according to native macOS status menu conventions with consistent text alignment,
// clean sectional dividers, and standard keyboard shortcuts.
import AppKit
import SwiftUI
import Combine
import Core

/// Manages the menu bar status icon for OpenClip.
@MainActor
class StatusBarController: NSObject, NSMenuDelegate {
    private let settingsStore: any SettingsStore
    private let notificationCenter: NotificationCenter
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var toggleEnabledItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var actionsSubmenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()

    var isMenuBarIconVisible: Bool { statusItem != nil }
    
    /// Initializes a new status bar controller.
    init(
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        super.init()
        
        notificationCenter.addObserver(
            self,
            selector: #selector(handleStateChanged(_:)),
            name: .openClipEnabledStateChanged,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleMenuBarVisibilityChanged(_:)),
            name: .openClipMenuBarVisibilityChanged,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleOpenConfiguration(_:)),
            name: .openClipOpenActionConfiguration,
            object: nil
        )

        setMenuBarIconVisible(settingsStore.get(.showMenuBarIcon))

        AppUpdateManager.shared.$availableUpdateVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] version in
                self?.updateUpdateMenuItem(version: version)
            }
            .store(in: &cancellables)

        AppUpdateManager.shared.$isUpdateStagedForQuitInstall
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUpdateMenuItem(version: AppUpdateManager.shared.availableUpdateVersion)
            }
            .store(in: &cancellables)
    }
    
    /// Sets up the menu for the status bar item following standard macOS menu hierarchy.
    private func setupMenu() {
        let menu = NSMenu()
        
        // Section 1: Core State Toggle
        let isEnabled = settingsStore.get(.isAppEnabled)
        let toggleItem = NSMenuItem(
            title: String(localized: "Appear Automatically"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)
        self.toggleEnabledItem = toggleItem
        
        menu.addItem(NSMenuItem.separator())

        // Section 2: Core App Navigation
        let prefsItem = menuItem(title: String(localized: "Settings…"), action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(prefsItem)

        let actionsMenu = NSMenu(title: String(localized: "Actions"))
        actionsMenu.delegate = self
        self.actionsSubmenu = actionsMenu
        
        let actionsItem = NSMenuItem(title: String(localized: "Actions"), action: nil, keyEquivalent: "")
        actionsItem.submenu = actionsMenu
        menu.addItem(actionsItem)
        
        menu.addItem(NSMenuItem.separator())

        // Section 3: Updates & Support
        let updateItem = menuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates))
        menu.addItem(updateItem)
        self.updateMenuItem = updateItem
        updateUpdateMenuItem(version: AppUpdateManager.shared.availableUpdateVersion)

        menu.addItem(menuItem(title: String(localized: "Report Issue…"), action: #selector(openReportIssue)))

        menu.addItem(NSMenuItem.separator())
        
        // Section 4: Lifecycle
        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.image = menuSymbolImage("power")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        updateStatusIcon(isEnabled: isEnabled)
    }

    private func updateUpdateMenuItem(version: String?) {
        guard let updateMenuItem else { return }
        if let version {
            if AppUpdateManager.shared.isUpdateStagedForQuitInstall {
                updateMenuItem.title = String(localized: "Update Ready on Quit (v\(version))…")
            } else {
                updateMenuItem.title = String(localized: "Update Available (v\(version))…")
            }
        } else {
            updateMenuItem.title = String(localized: "Check for Updates…")
        }
        updateMenuItem.image = nil
    }

    var updateMenuItemTitle: String? {
        updateMenuItem?.title
    }
    
    private func menuSymbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.size = NSSize(width: 14, height: 14)
        img?.isTemplate = true
        return img
    }

    /// Builds a menu item targeted at self (status-item menus don't resolve actions through the responder chain).
    private func menuItem(title: String, action: Selector, keyEquivalent: String = "", iconName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let iconName {
            item.image = menuSymbolImage(iconName)
        }
        return item
    }

    @objc private func toggleEnabled() {
        let current = settingsStore.get(.isAppEnabled)
        let newStatus = !current
        settingsStore.set(.isAppEnabled, value: newStatus)
        updateStatusItem(isEnabled: newStatus)
        notificationCenter.post(name: .openClipEnabledStateChanged, object: newStatus)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === actionsSubmenu else { return }
        menu.removeAllItems()

        // Top pinned action: immediately accessible with zero scrolling
        let manageItem = NSMenuItem(
            title: String(localized: "Manage Actions…"),
            action: #selector(openActionsTab),
            keyEquivalent: ""
        )
        manageItem.target = self
        menu.addItem(manageItem)

        menu.addItem(NSMenuItem.separator())

        let actions = ActionCoordinator.shared.actions
        let customGroupMemberIDs = Set(ActionCoordinator.shared.actionGroupDefs.flatMap(\.memberActionIDs))
        let disabledActionIDs = settingsStore.get(.disabledActionIDs)
        let isAIEnabled = settingsStore.get(.isAIEnabled)

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: customGroupMemberIDs,
            disabledActionIDs: disabledActionIDs,
            isAIEnabled: isAIEnabled,
            presentationProvider: { action in
                ActionCustomizationManager.shared.presented(action, surface: .table)
            }
        )

        if items.isEmpty {
            let emptyItem = NSMenuItem(title: String(localized: "No Actions Available"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(toggleActionItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item
            menuItem.state = item.isEnabled ? .on : .off
            menuItem.image = ActionIconImageHelper.menuImage(for: item.icon)
            menu.addItem(menuItem)
        }
    }

    @objc private func openActionsTab() {
        showPreferences(tab: .actions)
    }

    @objc private func toggleActionItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? TopLevelActionItem else { return }
        if item.isAI {
            let current = settingsStore.get(.isAIEnabled)
            let newStatus = !current
            settingsStore.set(.isAIEnabled, value: newStatus)
            AIServiceManager.shared.isAIEnabled = newStatus
            sender.state = newStatus ? .on : .off
            notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
        } else {
            var disabledActionIDs = settingsStore.get(.disabledActionIDs)
            let isCurrentlyDisabled = disabledActionIDs.contains(item.id)
            if isCurrentlyDisabled {
                disabledActionIDs.remove(item.id)
                settingsStore.set(.disabledActionIDs, value: disabledActionIDs)
                sender.state = .on
            } else {
                disabledActionIDs.insert(item.id)
                settingsStore.set(.disabledActionIDs, value: disabledActionIDs)
                sender.state = .off
            }
            notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
        }
    }
    
    @objc private func handleStateChanged(_ notification: Notification) {
        let isEnabled = (notification.object as? Bool) ?? settingsStore.get(.isAppEnabled)
        updateStatusItem(isEnabled: isEnabled)
    }

    @objc private func handleMenuBarVisibilityChanged(_ notification: Notification) {
        let isVisible = (notification.object as? Bool) ?? settingsStore.get(.showMenuBarIcon)
        setMenuBarIconVisible(isVisible)
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
        statusItem?.button?.window?.frame
    }
    
    private func updateStatusIcon(isEnabled: Bool) {
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            button.alphaValue = isEnabled ? 1.0 : 0.45
            // The enabled state must be legible beyond the purely visual alpha dimming.
            button.setAccessibilityLabel("OpenClip")
            button.setAccessibilityValue(isEnabled ? String(localized: "Appear Automatically is on") : String(localized: "Appear Automatically is off"))
        }
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            guard statusItem == nil else { return }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            setupMenu()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            toggleEnabledItem = nil
            actionsSubmenu = nil
        }
    }
    
    @objc public func showPreferences() {
        showPreferences(tab: .general)
    }

    public func showPreferences(tab: PreferenceTab = .general) {
        if let window = preferencesWindow, window.isVisible {
            notificationCenter.post(name: .openClipSelectPreferencesTab, object: tab)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: PreferencesView(initialTab: tab))
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "OpenClip Preferences")
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
