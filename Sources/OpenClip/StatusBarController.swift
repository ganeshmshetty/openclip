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
    private var rootMenu: NSMenu?
    internal var resumeItem: NSMenuItem?
    internal var toggleEnabledItem: NSMenuItem?
    internal var pauseAppItem: NSMenuItem?
    internal var pauseSubmenu: NSMenu?
    internal var updateMenuItem: NSMenuItem?
    internal var actionsSubmenu: NSMenu?
    internal var targetAppOverride: NSRunningApplication?
    private var lastActiveApp: NSRunningApplication?
    internal var currentTargetApp: NSRunningApplication? {
        get { targetAppOverride ?? resolveFrontmostApp() }
        set { targetAppOverride = newValue }
    }
    private var cancellables = Set<AnyCancellable>()

    var isMenuBarIconVisible: Bool { statusItem != nil }
    
    private let rulesSaveURL: URL
    private var pauseTask: Task<Void, Never>?

    /// Initializes a new status bar controller.
    init(
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        notificationCenter: NotificationCenter = .default,
        rulesSaveURL: URL = Constants.rulesFileURL
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.rulesSaveURL = rulesSaveURL
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if let front = NSWorkspace.shared.frontmostApplication, isValidTargetApp(front) {
            self.lastActiveApp = front
        }

        let pauseUntil = settingsStore.get(.pauseUntilTimestamp)
        let remaining = pauseUntil - Date().timeIntervalSince1970
        if remaining > 0 {
            schedulePauseTask(seconds: remaining)
        }
    }

    deinit {
        notificationCenter.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    /// Sets up the menu for the status bar item following standard macOS menu hierarchy.
    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        self.rootMenu = menu

        // Resume item (prominent when paused)
        let resume = NSMenuItem(
            title: String(localized: "Resume OpenClip"),
            action: #selector(resumeFromPause),
            keyEquivalent: ""
        )
        resume.target = self
        resume.isHidden = true
        menu.addItem(resume)
        self.resumeItem = resume
        
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

        // Dynamic Pause in <Current App>
        let pauseApp = NSMenuItem(
            title: String(localized: "Pause in App"),
            action: #selector(toggleCurrentAppPause),
            keyEquivalent: ""
        )
        pauseApp.target = self
        pauseApp.isHidden = true
        menu.addItem(pauseApp)
        self.pauseAppItem = pauseApp

        // Pause Submenu (Snooze)
        let pauseMenu = NSMenu(title: String(localized: "Pause"))
        let pause30 = menuItem(title: String(localized: "Pause for 30 Minutes"), action: #selector(pause30Minutes))
        let pause60 = menuItem(title: String(localized: "Pause for 1 Hour"), action: #selector(pause1Hour))
        let pauseDay = menuItem(title: String(localized: "Pause Until Tomorrow"), action: #selector(pauseUntilTomorrow))
        pauseMenu.addItem(pause30)
        pauseMenu.addItem(pause60)
        pauseMenu.addItem(pauseDay)
        self.pauseSubmenu = pauseMenu

        let pauseParent = NSMenuItem(title: String(localized: "Pause"), action: nil, keyEquivalent: "")
        pauseParent.submenu = pauseMenu
        menu.addItem(pauseParent)
        
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

    func menuWillOpen(_ menu: NSMenu) {
        if menu === rootMenu {
            updateRootMenuDynamicItems()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === rootMenu {
            updateRootMenuDynamicItems()
            return
        }
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

    internal func updateRootMenuDynamicItems() {
        let isEnabled = settingsStore.get(.isAppEnabled)
        toggleEnabledItem?.state = isEnabled ? .on : .off

        let pauseUntil = settingsStore.get(.pauseUntilTimestamp)
        let isPaused = pauseUntil > Date().timeIntervalSince1970
        if isPaused {
            let remainingSeconds = pauseUntil - Date().timeIntervalSince1970
            let mins = max(1, Int(ceil(remainingSeconds / 60.0)))
            resumeItem?.title = String(localized: "Resume OpenClip (\(mins)m left)")
            resumeItem?.isHidden = false
        } else {
            resumeItem?.isHidden = true
        }

        let frontApp = currentTargetApp
        if let frontApp, let bundleID = frontApp.bundleIdentifier {
            let appName = frontApp.localizedName ?? String(localized: "Current App")
            let policy = RuleEngine.shared.resolvePolicies(for: bundleID)
            let isAppDisabled = policy.disabled

            pauseAppItem?.isHidden = false
            if isAppDisabled {
                pauseAppItem?.title = String(localized: "Paused in \(appName)")
                pauseAppItem?.state = .on
            } else {
                pauseAppItem?.title = String(localized: "Pause in \(appName)")
                pauseAppItem?.state = .off
            }
            pauseAppItem?.image = nil
        } else {
            pauseAppItem?.isHidden = true
        }

        updateStatusIcon(isEnabled: isEnabled)
    }

    @objc private func handleWorkspaceAppActivated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           isValidTargetApp(app) {
            lastActiveApp = app
        }
    }

    private func isValidTargetApp(_ app: NSRunningApplication?) -> Bool {
        guard let app,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !AppFilter.isExcluded(bundleID: bundleID),
              app.activationPolicy == .regular else {
            return false
        }
        return true
    }

    private func resolveFrontmostApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, isValidTargetApp(front) {
            lastActiveApp = front
            return front
        }
        return lastActiveApp
    }

    @objc internal func pause30Minutes() {
        pauseFor(seconds: 1800)
    }

    @objc internal func pause1Hour() {
        pauseFor(seconds: 3600)
    }

    @objc internal func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let seconds = tomorrow.timeIntervalSince(now)
        pauseFor(seconds: seconds)
    }

    @objc internal func resumeFromPause() {
        pauseTask?.cancel()
        pauseTask = nil
        settingsStore.set(.pauseUntilTimestamp, value: 0.0)
        updateStatusItem(isEnabled: settingsStore.get(.isAppEnabled))
        notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
    }

    private func schedulePauseTask(seconds: TimeInterval) {
        pauseTask?.cancel()
        pauseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0.1, seconds) * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.settingsStore.set(.pauseUntilTimestamp, value: 0.0)
            self.pauseTask = nil
            self.updateStatusItem(isEnabled: self.settingsStore.get(.isAppEnabled))
            self.notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
        }
    }

    internal func pauseFor(seconds: TimeInterval) {
        let target = Date().timeIntervalSince1970 + seconds
        settingsStore.set(.pauseUntilTimestamp, value: target)
        schedulePauseTask(seconds: seconds)
        updateStatusItem(isEnabled: settingsStore.get(.isAppEnabled))
        notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
    }

    @objc internal func toggleCurrentAppPause() {
        guard let app = currentTargetApp, let bundleID = app.bundleIdentifier else { return }
        let policy = RuleEngine.shared.resolvePolicies(for: bundleID)
        if policy.disabled {
            if let existingRule = RuleEngine.shared.userRules.first(where: { $0.bundleIdentifiers.contains(bundleID) }) {
                if existingRule.bundleIdentifiers.count > 1 {
                    let remainingIDs = existingRule.bundleIdentifiers.filter { $0 != bundleID }
                    let updatedRule = AppRule(
                        bundleIdentifiers: remainingIDs,
                        disabled: existingRule.disabled,
                        hotkeyOnly: existingRule.hotkeyOnly,
                        useMenuCopy: existingRule.useMenuCopy,
                        denyPaste: existingRule.denyPaste,
                        retrievalMode: existingRule.retrievalMode,
                        gate: existingRule.gate
                    )
                    RuleEngine.shared.removeRule(id: existingRule.id, saveURL: rulesSaveURL)
                    RuleEngine.shared.addOrUpdateRule(updatedRule, saveURL: rulesSaveURL)
                } else if existingRule.hotkeyOnly != nil || existingRule.useMenuCopy != nil || existingRule.denyPaste != nil || existingRule.retrievalMode != nil || existingRule.gate != nil {
                    let updatedRule = AppRule(
                        bundleIdentifiers: [bundleID],
                        disabled: false,
                        hotkeyOnly: existingRule.hotkeyOnly,
                        useMenuCopy: existingRule.useMenuCopy,
                        denyPaste: existingRule.denyPaste,
                        retrievalMode: existingRule.retrievalMode,
                        gate: existingRule.gate
                    )
                    RuleEngine.shared.addOrUpdateRule(updatedRule, saveURL: rulesSaveURL)
                } else {
                    RuleEngine.shared.removeRule(id: existingRule.id, saveURL: rulesSaveURL)
                }
            } else {
                let overrideRule = AppRule(bundleIdentifiers: [bundleID], disabled: false)
                RuleEngine.shared.addOrUpdateRule(overrideRule, saveURL: rulesSaveURL)
            }
        } else {
            if let existingRule = RuleEngine.shared.userRules.first(where: { $0.bundleIdentifiers.contains(bundleID) }) {
                if existingRule.bundleIdentifiers == [bundleID] {
                    let updatedRule = AppRule(
                        bundleIdentifiers: [bundleID],
                        disabled: true,
                        hotkeyOnly: existingRule.hotkeyOnly,
                        useMenuCopy: existingRule.useMenuCopy,
                        denyPaste: existingRule.denyPaste,
                        retrievalMode: existingRule.retrievalMode,
                        gate: existingRule.gate
                    )
                    RuleEngine.shared.addOrUpdateRule(updatedRule, saveURL: rulesSaveURL)
                } else {
                    let remainingIDs = existingRule.bundleIdentifiers.filter { $0 != bundleID }
                    let updatedRule = AppRule(
                        bundleIdentifiers: remainingIDs,
                        disabled: existingRule.disabled,
                        hotkeyOnly: existingRule.hotkeyOnly,
                        useMenuCopy: existingRule.useMenuCopy,
                        denyPaste: existingRule.denyPaste,
                        retrievalMode: existingRule.retrievalMode,
                        gate: existingRule.gate
                    )
                    RuleEngine.shared.removeRule(id: existingRule.id, saveURL: rulesSaveURL)
                    RuleEngine.shared.addOrUpdateRule(updatedRule, saveURL: rulesSaveURL)

                    let rule = AppRule(bundleIdentifiers: [bundleID], disabled: true)
                    RuleEngine.shared.addOrUpdateRule(rule, saveURL: rulesSaveURL)
                }
            } else {
                let rule = AppRule(bundleIdentifiers: [bundleID], disabled: true)
                RuleEngine.shared.addOrUpdateRule(rule, saveURL: rulesSaveURL)
            }
        }
        updateRootMenuDynamicItems()
        notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
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
        let isPaused = settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970
        let effectiveEnabled = isEnabled && !isPaused
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            button.alphaValue = effectiveEnabled ? 1.0 : 0.45
            // The enabled state must be legible beyond the purely visual alpha dimming.
            button.setAccessibilityLabel("OpenClip")
            if isPaused {
                button.setAccessibilityValue(String(localized: "OpenClip is paused"))
            } else {
                button.setAccessibilityValue(isEnabled ? String(localized: "Appear Automatically is on") : String(localized: "Appear Automatically is off"))
            }
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
            resumeItem = nil
            pauseAppItem = nil
            pauseSubmenu = nil
            rootMenu = nil
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
        window.setContentSize(NSSize(width: 760, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
