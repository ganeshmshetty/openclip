// StatusBarController.swift
// OpenClip
//
// Menu bar status item, its dropdown menu, and Preferences presentation.
import AppKit
import SwiftUI
import Combine
import Core
import KeyboardShortcuts

@MainActor
class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let settingsStore: any SettingsStore
    private let notificationCenter: NotificationCenter
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var preferencesToolbarController: PreferencesToolbarController?
    internal var rootMenu: NSMenu?
    internal var captureTextMenuItem: NSMenuItem?
    internal var settingsMenuItem: NSMenuItem?
    internal var actionsMenuItem: NSMenuItem?
    internal var resumeItem: NSMenuItem?
    internal var toggleEnabledItem: NSMenuItem?
    internal var disableAppItem: NSMenuItem?
    internal var disableAppSeparatorItem: NSMenuItem?
    internal var pauseSubmenu: NSMenu?
    internal var pauseParentMenuItem: NSMenuItem?
    internal var updateMenuItem: NSMenuItem?
    internal var actionsSubmenu: NSMenu?
    internal var targetAppOverride: NSRunningApplication?
    var onCaptureText: ((NSRunningApplication?) -> Void)?
    private var lastActiveApp: NSRunningApplication?
    internal var currentTargetApp: NSRunningApplication? {
        get { targetAppOverride ?? resolveFrontmostApp() }
        set { targetAppOverride = newValue }
    }
    private var cancellables = Set<AnyCancellable>()

    var isMenuBarIconVisible: Bool { statusItem != nil }
    
    private let rulesSaveURL: URL
    private var pauseTask: Task<Void, Never>?

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

        AppUpdateManager.shared.$hasUpdateReminder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStatusIcon(isEnabled: self.settingsStore.get(.isAppEnabled))
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
    
    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        self.rootMenu = menu

        let resume = NSMenuItem(
            title: String(localized: "Resume OpenClip"),
            action: #selector(resumeFromPause),
            keyEquivalent: ""
        )
        resume.target = self
        resume.isHidden = true
        menu.addItem(resume)
        self.resumeItem = resume
        
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

        let disableApp = NSMenuItem(
            title: String(localized: "Disable in App"),
            action: #selector(toggleCurrentAppDisabled),
            keyEquivalent: ""
        )
        disableApp.target = self
        disableApp.isHidden = true
        menu.addItem(disableApp)
        self.disableAppItem = disableApp

        let disableAppSep = NSMenuItem.separator()
        disableAppSep.isHidden = true
        menu.addItem(disableAppSep)
        self.disableAppSeparatorItem = disableAppSep

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
        self.pauseParentMenuItem = pauseParent
        
        menu.addItem(NSMenuItem.separator())

        let captureItem = menuItem(title: String(localized: "Capture Text"), action: #selector(captureText))
        captureItem.setShortcut(for: .captureText)
        self.captureTextMenuItem = captureItem
        menu.addItem(captureItem)

        let actionsMenu = NSMenu(title: String(localized: "Actions"))
        actionsMenu.delegate = self
        self.actionsSubmenu = actionsMenu

        let actionsItem = NSMenuItem(title: String(localized: "Actions"), action: nil, keyEquivalent: "")
        actionsItem.submenu = actionsMenu
        self.actionsMenuItem = actionsItem
        menu.addItem(actionsItem)

        let prefsItem = menuItem(title: String(localized: "Settings…"), action: #selector(showPreferences as () -> Void), keyEquivalent: ",")
        self.settingsMenuItem = prefsItem
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())

        let updateItem = menuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates))
        menu.addItem(updateItem)
        self.updateMenuItem = updateItem
        updateUpdateMenuItem(version: AppUpdateManager.shared.availableUpdateVersion)

        menu.addItem(menuItem(title: String(localized: "Report Issue…"), action: #selector(openReportIssue)))

        menu.addItem(NSMenuItem.separator())
        
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
        updateMenuItem.isEnabled = AppUpdateManager.shared.updatesEnabled
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

    /// Targets self explicitly: status-item menus don't resolve actions via the responder chain.
    private func menuItem(title: String, action: Selector, keyEquivalent: String = "", iconName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let iconName {
            item.image = menuSymbolImage(iconName)
        }
        return item
    }

    @objc internal func toggleEnabled() {
        let current = settingsStore.get(.isAppEnabled)
        let newStatus = !current
        settingsStore.set(.isAppEnabled, value: newStatus)
        updateStatusItem(isEnabled: newStatus)
        notificationCenter.post(name: .openClipEnabledStateChanged, object: newStatus)
    }


    @objc private func captureText() {
        let app = currentTargetApp
        DispatchQueue.main.async { [weak self] in self?.onCaptureText?(app) }
    }

    // MARK: - NSMenuDelegate

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return AppUpdateManager.shared.updatesEnabled
        }
        return menuItem.isEnabled
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === rootMenu {
            KeyboardShortcuts.disable(.captureText)
            updateRootMenuDynamicItems()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === rootMenu {
            KeyboardShortcuts.enable(.captureText)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === rootMenu {
            updateRootMenuDynamicItems()
            return
        }
        guard menu === actionsSubmenu else { return }
        menu.removeAllItems()

        // Pinned at top, reachable without scrolling.
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

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: customGroupMemberIDs,
            disabledActionIDs: disabledActionIDs,
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
        var disabledActionIDs = settingsStore.get(.disabledActionIDs)
        if disabledActionIDs.contains(item.id) {
            disabledActionIDs.remove(item.id)
            sender.state = .on
        } else {
            disabledActionIDs.insert(item.id)
            sender.state = .off
        }
        settingsStore.set(.disabledActionIDs, value: disabledActionIDs)
        notificationCenter.post(name: .openClipEnabledStateChanged, object: nil)
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
        let frontIdentity = frontApp.map { AppIdentity($0) }
        if let frontApp, let identity = frontIdentity, identity.ruleIdentifier != nil {
            let appName = frontApp.localizedName ?? identity.processName ?? String(localized: "Current App")
            let policy = RuleEngine.shared.resolvePolicies(for: identity)
            let isAppDisabled = policy.disabled

            disableAppItem?.isHidden = false
            disableAppSeparatorItem?.isHidden = false
            disableAppItem?.title = isAppDisabled
                ? String(localized: "Disabled in \(appName)")
                : String(localized: "Disable in \(appName)")
            disableAppItem?.state = isAppDisabled ? .on : .off
            disableAppItem?.image = nil
        } else {
            disableAppItem?.isHidden = true
            disableAppSeparatorItem?.isHidden = true
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
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.activationPolicy == .regular else {
            return false
        }
        // Bundle-less processes (CLI tools such as scrcpy) are targetable via name/path.
        return app.bundleIdentifier.map { !AppFilter.isExcluded(bundleID: $0) }
            ?? (AppIdentity(app).ruleIdentifier != nil)
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

    @objc internal func toggleCurrentAppDisabled() {
        guard let app = currentTargetApp else { return }
        let identity = AppIdentity(app)
        guard let identifier = identity.ruleIdentifier else { return }
        let policy = RuleEngine.shared.resolvePolicies(for: identity)
        if policy.disabled {
            if let existingRule = RuleEngine.shared.userRules.first(where: { $0.bundleIdentifiers.contains(identifier) }) {
                if existingRule.bundleIdentifiers.count > 1 {
                    let remainingIDs = existingRule.bundleIdentifiers.filter { $0 != identifier }
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
                        bundleIdentifiers: [identifier],
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
                let overrideRule = AppRule(bundleIdentifiers: [identifier], disabled: false)
                RuleEngine.shared.addOrUpdateRule(overrideRule, saveURL: rulesSaveURL)
            }
        } else {
            if let existingRule = RuleEngine.shared.userRules.first(where: { $0.bundleIdentifiers.contains(identifier) }) {
                if existingRule.bundleIdentifiers == [identifier] {
                    let updatedRule = AppRule(
                        bundleIdentifiers: [identifier],
                        disabled: true,
                        hotkeyOnly: existingRule.hotkeyOnly,
                        useMenuCopy: existingRule.useMenuCopy,
                        denyPaste: existingRule.denyPaste,
                        retrievalMode: existingRule.retrievalMode,
                        gate: existingRule.gate
                    )
                    RuleEngine.shared.addOrUpdateRule(updatedRule, saveURL: rulesSaveURL)
                } else {
                    let remainingIDs = existingRule.bundleIdentifiers.filter { $0 != identifier }
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

                    let rule = AppRule(bundleIdentifiers: [identifier], disabled: true)
                    RuleEngine.shared.addOrUpdateRule(rule, saveURL: rulesSaveURL)
                }
            } else {
                let rule = AppRule(bundleIdentifiers: [identifier], disabled: true)
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
    
    /// An action asked to be configured: open Preferences, which presents its editor.
    @objc private func handleOpenConfiguration(_ notification: Notification) {
        showPreferences()
    }
    
    public func updateStatusItem(isEnabled: Bool) {
        toggleEnabledItem?.state = isEnabled ? .on : .off
        updateStatusIcon(isEnabled: isEnabled)
    }

    /// Screen frame of the status item button; nil while it is hidden or has not joined a window.
    var statusItemButtonFrame: NSRect? {
        guard let statusItem, statusItem.isVisible,
              let frame = statusItem.button?.window?.frame,
              !frame.isEmpty else { return nil }
        return frame
    }
    
    private func updateStatusIcon(isEnabled: Bool) {
        let isPaused = settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970
        let effectiveEnabled = isEnabled && !isPaused
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "paperclip", accessibilityDescription: "OpenClip")
            button.image?.isTemplate = true
            let hasReminder = AppUpdateManager.shared.hasUpdateReminder
            button.title = hasReminder ? "•" : ""
            button.font = .systemFont(ofSize: 9, weight: .bold)
            button.imagePosition = .imageLeft
            button.toolTip = hasReminder ? String(localized: "OpenClip Update Available") : "OpenClip"
            button.alphaValue = effectiveEnabled ? 1.0 : 0.45
            // Don't convey enabled state by alpha alone (accessibility).
            button.setAccessibilityLabel(hasReminder ? String(localized: "OpenClip Update Available") : "OpenClip")
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
            disableAppItem = nil
            disableAppSeparatorItem = nil
            pauseSubmenu = nil
            pauseParentMenuItem = nil
            rootMenu = nil
            actionsSubmenu = nil
        }
    }
    
    /// Opens Settings on the last-shown pane and drill-down; resetting here would lose the router path.
    @objc public func showPreferences() {
        presentPreferences(tab: nil)
    }

    /// Opens Settings on a named pane, overriding the last-shown one.
    public func showPreferences(tab: PreferenceTab) {
        presentPreferences(tab: tab)
    }

    private func presentPreferences(tab: PreferenceTab?) {
        SettingsWindowController.show(tab: tab)
    }
}
