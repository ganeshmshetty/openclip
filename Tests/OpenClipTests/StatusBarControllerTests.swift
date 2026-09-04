import XCTest
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

    func testToggleCurrentAppPauseAddsAndRemovesDisabledRule() {
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
        XCTAssertEqual(controller.pauseAppItem?.isHidden, false)
        XCTAssertEqual(controller.pauseAppItem?.state, .off)
        XCTAssertEqual(controller.pauseAppItem?.title, "Pause in Safari")
        XCTAssertNil(controller.pauseAppItem?.image)

        // Toggle pause for Safari
        controller.toggleCurrentAppPause()
        let policyAfterPause = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertTrue(policyAfterPause.disabled, "Safari should now be disabled")
        XCTAssertEqual(controller.pauseAppItem?.state, .on)
        XCTAssertEqual(controller.pauseAppItem?.title, "Paused in Safari")
        XCTAssertFalse(controller.pauseAppItem?.title.contains("Click to Resume") == true)
        XCTAssertNil(controller.pauseAppItem?.image)

        // Toggle resume for Safari
        controller.toggleCurrentAppPause()
        let policyAfterResume = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertFalse(policyAfterResume.disabled, "Safari should no longer be disabled")
        XCTAssertEqual(controller.pauseAppItem?.state, .off)
        XCTAssertEqual(controller.pauseAppItem?.title, "Pause in Safari")
        XCTAssertNil(controller.pauseAppItem?.image)
    }

    func testToggleCurrentAppPausePreservesMultiAppRule() {
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
        controller.toggleCurrentAppPause()

        // Safari should now be enabled, but Chrome must remain disabled
        XCTAssertFalse(RuleEngine.shared.resolvePolicies(for: "com.apple.Safari").disabled)
        XCTAssertTrue(RuleEngine.shared.resolvePolicies(for: "com.google.Chrome").disabled)
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
