import XCTest
import KeyboardShortcuts
@testable import Core
@testable import OpenClip

@MainActor
final class StatusBarControllerTests: XCTestCase {
    private var tempRulesURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempRulesURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        await MainActor.run { TestIsolation.reset() }
        if let tempRulesURL {
            try? FileManager.default.removeItem(at: tempRulesURL)
        }
        try await super.tearDown()
    }

    func testStartsWithoutStatusItemWhenPreferenceIsDisabled() {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: false)
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        XCTAssertFalse(controller.isMenuBarIconVisible)
    }

    func testCaptureTextMenuItemShowsConfiguredShortcutAndIsGroupedAboveSettings() {
        let controller = StatusBarController(
            settingsStore: MemorySettingsStore(),
            notificationCenter: NotificationCenter(),
            rulesSaveURL: tempRulesURL
        )
        guard let captureItem = controller.captureTextMenuItem,
              let settingsItem = controller.settingsMenuItem,
              let actionsItem = controller.actionsMenuItem,
              let items = controller.rootMenu?.items else {
            return XCTFail("Expected the status menu navigation items")
        }

        XCTAssertEqual(captureItem.title, "Capture Text")
        XCTAssertLessThan(items.firstIndex(of: captureItem)!, items.firstIndex(of: actionsItem)!)
        XCTAssertLessThan(items.firstIndex(of: actionsItem)!, items.firstIndex(of: settingsItem)!)

        let savedShortcut = KeyboardShortcuts.getShortcut(for: .captureText)
        defer { KeyboardShortcuts.setShortcut(savedShortcut, for: .captureText) }

        KeyboardShortcuts.setShortcut(.init(.x, modifiers: [.command, .option]), for: .captureText)
        XCTAssertEqual(captureItem.keyEquivalent, "x")
        XCTAssertEqual(captureItem.keyEquivalentModifierMask, [.command, .option])

        KeyboardShortcuts.setShortcut(nil, for: .captureText)
        XCTAssertEqual(captureItem.keyEquivalent, "")
    }

    func testVisibilityNotificationRemovesAndRecreatesStatusItem() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        XCTAssertTrue(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: false)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: false)
        XCTAssertFalse(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: true)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: true)
        XCTAssertTrue(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: false)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: false)
    }

    func testPauseForSetsTimestampAndUpdatesResumeItem() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        XCTAssertEqual(store.get(.pauseUntilTimestamp), 0.0)
        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.resumeItem?.isHidden, true)

        // Pause for 30 minutes
        controller.pause30Minutes()
        let timestamp = store.get(.pauseUntilTimestamp)
        XCTAssertGreaterThan(timestamp, Date().timeIntervalSince1970 + 1700)

        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.resumeItem?.isHidden, false)
        XCTAssertTrue(controller.resumeItem?.title.contains("Resume OpenClip") == true)
    }

    func testPauseTimerResetsTimestampWhenFired() async throws {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        controller.pauseFor(seconds: 0.1)
        XCTAssertGreaterThan(store.get(.pauseUntilTimestamp), 0.0)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.get(.pauseUntilTimestamp), 0.0)
    }

    func testResumeFromPauseClearsTimestampAndHidesResumeItem() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        // Pre-set a future pause timestamp
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)
        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.resumeItem?.isHidden, false)

        controller.resumeFromPause()
        XCTAssertEqual(store.get(.pauseUntilTimestamp), 0.0)

        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.resumeItem?.isHidden, true)
    }

    func testToggleCurrentAppDisabledAddsAndRemovesRule() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        let mockSafari = MockStatusBarApp(bundleID: "com.apple.Safari", localizedName: "Safari")
        controller.currentTargetApp = mockSafari

        // Initially Safari is not disabled
        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.disableAppItem?.isHidden, false)
        XCTAssertEqual(controller.disableAppItem?.state, .off)
        XCTAssertEqual(controller.disableAppItem?.title, "Disable in Safari")
        XCTAssertNil(controller.disableAppItem?.image)

        // Toggle pause for Safari
        controller.toggleCurrentAppDisabled()
        let policyAfterPause = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertTrue(policyAfterPause.disabled, "Safari should now be disabled")
        XCTAssertEqual(controller.disableAppItem?.state, .on)
        XCTAssertEqual(controller.disableAppItem?.title, "Disabled in Safari")
        XCTAssertFalse(controller.disableAppItem?.title.contains("Click to Resume") == true)
        XCTAssertNil(controller.disableAppItem?.image)

        // Toggle resume for Safari
        controller.toggleCurrentAppDisabled()
        let policyAfterResume = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertFalse(policyAfterResume.disabled, "Safari should no longer be disabled")
        XCTAssertEqual(controller.disableAppItem?.state, .off)
        XCTAssertEqual(controller.disableAppItem?.title, "Disable in Safari")
        XCTAssertNil(controller.disableAppItem?.image)
    }

    func testToggleCurrentAppDisabledPreservesMultiAppRule() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: notificationCenter,
            rulesSaveURL: tempRulesURL
        )

        // Seed multi-app disabled rule
        let multiAppRule = AppRule(bundleIdentifiers: ["com.apple.Safari", "com.google.Chrome"], disabled: true)
        RuleEngine.shared.addOrUpdateRule(multiAppRule, saveURL: tempRulesURL)

        let mockSafari = MockStatusBarApp(bundleID: "com.apple.Safari", localizedName: "Safari")
        controller.currentTargetApp = mockSafari

        // Unpause Safari
        controller.toggleCurrentAppDisabled()

        // Safari should now be enabled, but Chrome must remain disabled
        XCTAssertFalse(RuleEngine.shared.resolvePolicies(for: "com.apple.Safari").disabled)
        XCTAssertTrue(RuleEngine.shared.resolvePolicies(for: "com.google.Chrome").disabled)
    }

    func testAppearAutomaticallyMenuItemTogglesState() {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: true)
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: NotificationCenter(),
            rulesSaveURL: tempRulesURL
        )
        guard let toggleItem = controller.toggleEnabledItem else {
            return XCTFail("Expected toggleEnabledItem to be present")
        }

        XCTAssertEqual(toggleItem.title, "Appear Automatically")
        XCTAssertEqual(toggleItem.state, .on)

        store.set(.isAppEnabled, value: false)
        controller.updateStatusItem(isEnabled: false)
        XCTAssertEqual(toggleItem.state, .off)

        controller.toggleEnabled()
        XCTAssertTrue(store.get(.isAppEnabled))
        XCTAssertEqual(toggleItem.state, .on)
    }

    func testDisableAppItemIsTopLevelAndHidesWithoutApp() {
        let store = MemorySettingsStore()
        let controller = StatusBarController(
            settingsStore: store,
            notificationCenter: NotificationCenter(),
            rulesSaveURL: tempRulesURL
        )

        guard let rootMenu = controller.rootMenu,
              let pauseSubmenu = controller.pauseSubmenu,
              let disableItem = controller.disableAppItem,
              let disableSep = controller.disableAppSeparatorItem else {
            return XCTFail("Expected rootMenu, pauseSubmenu, disableAppItem, and separator")
        }

        XCTAssertTrue(rootMenu.items.contains(disableItem))
        XCTAssertTrue(rootMenu.items.contains(disableSep))
        XCTAssertFalse(pauseSubmenu.items.contains(disableItem), "disabling an app is permanent, not a timed pause")
        XCTAssertLessThan(rootMenu.items.firstIndex(of: disableItem)!, rootMenu.items.firstIndex(of: disableSep)!)

        // With mock app:
        let mockSafari = MockStatusBarApp(bundleID: "com.apple.Safari", localizedName: "Safari")
        controller.currentTargetApp = mockSafari
        controller.updateRootMenuDynamicItems()
        XCTAssertFalse(disableItem.isHidden)
        XCTAssertFalse(disableSep.isHidden)

        // Without valid app:
        controller.currentTargetApp = MockStatusBarApp(bundleID: nil)
        controller.updateRootMenuDynamicItems()
        XCTAssertTrue(disableItem.isHidden)
        XCTAssertTrue(disableSep.isHidden)
    }

    func testDefaultBlockedAppShowsDisabledAndCanBeReEnabled() {
        let controller = StatusBarController(
            settingsStore: MemorySettingsStore(),
            notificationCenter: NotificationCenter(),
            rulesSaveURL: tempRulesURL
        )
        controller.currentTargetApp = MockStatusBarApp(bundleID: "com.utmapp.UTM", localizedName: "UTM")

        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.disableAppItem?.state, .on)
        XCTAssertEqual(controller.disableAppItem?.title, "Disabled in UTM")

        controller.toggleCurrentAppDisabled()
        XCTAssertFalse(RuleEngine.shared.resolvePolicies(for: "com.utmapp.UTM").disabled)
        XCTAssertEqual(controller.disableAppItem?.state, .off)
        XCTAssertEqual(controller.disableAppItem?.title, "Disable in UTM")
    }

    func testMenuItemWithImagePrefersVisibleImage() {
        let item = NSMenuItem(title: "Capture Text", action: nil, keyEquivalent: "")
        item.image = NSImage(size: NSSize(width: 14, height: 14))

        item.preferVisibleImage()

        if #available(macOS 27.0, *) {
            XCTAssertEqual(item.preferredImageVisibility, .visible)
        }
    }

    func testMenuItemWithoutImageLeavesVisibilityAlone() {
        let item = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")

        item.preferVisibleImage()

        if #available(macOS 27.0, *) {
            XCTAssertEqual(item.preferredImageVisibility, .automatic)
        }
    }

    func testStatusMenuActionItemsBuiltFromRegistryPreferVisibleImages() {
        ActionRegistry.shared.register(
            action: StatusMenuAction(id: "test.menu.symbol", title: "Symbol Action", icon: .symbol("star"))
        )
        ActionRegistry.shared.register(
            action: StatusMenuAction(id: "test.menu.text", title: "Text Action", icon: .text("T"))
        )

        let controller = StatusBarController(
            settingsStore: MemorySettingsStore(),
            notificationCenter: NotificationCenter(),
            rulesSaveURL: tempRulesURL
        )
        controller.updateRootMenuDynamicItems()

        guard let actionsSubmenu = controller.actionsSubmenu else {
            return XCTFail("Expected the actions submenu")
        }
        controller.menuNeedsUpdate(actionsSubmenu)

        let actionItems = actionsSubmenu.items.filter { $0.image != nil }
        XCTAssertEqual(actionItems.count, 2, "both real action items should carry an image")
        XCTAssertEqual(Set(actionItems.map(\.title)), ["Symbol Action", "Text Action"])
        XCTAssertNotNil(controller.rootMenu)

        if #available(macOS 27.0, *) {
            for item in actionItems {
                XCTAssertEqual(item.preferredImageVisibility, .visible, "\(item.title) lost its image")
            }
        }
    }
}

private final class MockStatusBarApp: NSRunningApplication {
    private let bundleID: String?
    private let locName: String?

    init(bundleID: String?, localizedName: String? = nil) {
        self.bundleID = bundleID
        self.locName = localizedName
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var localizedName: String? { locName }
}

private struct StatusMenuAction: Action, Sendable {
    let id: String
    let title: String
    let icon: ActionIcon
    let chrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
