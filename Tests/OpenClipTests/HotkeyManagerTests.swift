import XCTest
import AppKit
import KeyboardShortcuts
@testable import OpenClip
@testable import Core

/// Regression coverage for the hotkey trigger path: ⌥⌘C must obey the gating that actually
/// applies to an explicit request — Pause, app exclusion (including OpenClip itself), per-app
/// `disabled` rules, and the text substantiality/length contract — instead of retrieving and
/// injecting a synthetic ⌘C into any frontmost app unconditionally. "Appear Automatically" is
/// **not** one of those gates: it owns the automatic popup only.
@MainActor
final class HotkeyManagerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            HotkeyManager.shared.selectionMonitor = nil
        }
    }

    /// "Appear Automatically" off means the popup stops following selections — the shortcut is an
    /// explicit request and must still work. It used to be gated on the same setting, so the
    /// hotkey silently did nothing whenever the toggle was off.
    func testAutomaticAppearanceOffStillAllowsTheHotkey() {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: false)
        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: app, settingsStore: store))
    }

    func testNoIdentifiableTargetNeverTriggers() {
        // Covers both a nil frontmost app and one without a bundle ID: previously this fell back
        // to OpenClip itself.
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: nil))
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: MockFrontmostApp(bundleID: nil)))
    }

    func testExcludedAppsNeverTrigger() {
        // A bundle from AppFilter's exclusion list must be rejected even when enabled.
        let excluded = MockFrontmostApp(bundleID: "com.adobe.photoshop")
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: excluded))
    }

    func testAppWithDisabledRuleNeverTriggers() {
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.test.disabled"], disabled: true))
        let app = MockFrontmostApp(bundleID: "com.test.disabled")
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: app))
    }

    func testAppWithHotkeyOnlyRuleTriggers() {
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.test.hotkeyonly"], hotkeyOnly: true))
        let app = MockFrontmostApp(bundleID: "com.test.hotkeyonly")
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: app))
    }

    func testOrdinaryForegroundAppTriggers() {
        let ordinary = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: ordinary))
    }

    func testPauseUntilTimestampBlocksTrigger() {
        let store = MemorySettingsStore()
        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")

        // Unpaused: allowed
        store.set(.pauseUntilTimestamp, value: 0.0)
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: app, settingsStore: store))

        // Paused in future: blocked
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: app, settingsStore: store))

        // Expired pause in past: allowed
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 - 10)
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: app, settingsStore: store))
    }

    func testActionHotkeyNameIsDeterministicAndUnique() {
        let nameA = KeyboardShortcuts.Name.actionHotkey("com.example.one")
        let nameA2 = KeyboardShortcuts.Name.actionHotkey("com.example.one")
        let nameB = KeyboardShortcuts.Name.actionHotkey("com.example.two")
        XCTAssertEqual(nameA, nameA2)
        XCTAssertNotEqual(nameA, nameB)
    }

    func testRunBoundActionPerformsActionOnController() async throws {
        let controller = PopupWindowController()
        let performedExpectation = expectation(description: "Bound action performed")
        let action = BoundTestAction(id: "test.bound") {
            performedExpectation.fulfill()
        }
        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection, modifiers: [])
        controller.runBoundAction(action, with: context)
        await fulfillment(of: [performedExpectation], timeout: 2.0)
    }

    func testCollectTriggerReusesMonitoredSelection() async throws {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let selection = SelectionContext(
            text: "monitored text",
            sourceApp: app,
            cursorPosition: CGPoint(x: 50, y: 50),
            selectionBounds: CGRect(x: 10, y: 10, width: 100, height: 20),
            timestamp: Date(),
            appPolicy: .default
        )
        monitor.latestSelection = (context: selection, canPaste: true)
        manager.selectionMonitor = monitor

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = await manager.collectTrigger(frontmostApp: frontmost)

        let result = try XCTUnwrap(trigger)
        XCTAssertEqual(result.context.text, "monitored text")
        XCTAssertEqual(result.canPaste, true)
        XCTAssertEqual(result.context.selectionBounds, CGRect(x: 10, y: 10, width: 100, height: 20))
    }

    func testCollectTriggerIgnoresMismatchedMonitoredSelection() async throws {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        let app = AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        let selection = SelectionContext(
            text: "safari text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        monitor.latestSelection = (context: selection, canPaste: false)
        manager.selectionMonitor = monitor

        // App filter would reject if com.openclip, but TextEdit is ordinary
        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        // Mismatched bundle ID means currentSelection returns nil, so the mismatched monitored selection is ignored
        let trigger = await manager.collectTrigger(frontmostApp: frontmost)
        XCTAssertNotEqual(trigger?.context.text, "safari text")
    }

    func testResolveSynchronousTriggerReusesMonitoredSelection() {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let selection = SelectionContext(
            text: "monitored sync text",
            sourceApp: app,
            cursorPosition: CGPoint(x: 50, y: 50),
            selectionBounds: CGRect(x: 10, y: 10, width: 100, height: 20),
            timestamp: Date(),
            appPolicy: .default
        )
        monitor.latestSelection = (context: selection, canPaste: true)
        manager.selectionMonitor = monitor

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = manager.resolveSynchronousTrigger(frontmostApp: frontmost)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "monitored sync text")
        XCTAssertEqual(result?.canPaste, true)
    }

    func testResolveSynchronousTriggerFallsBackToClipboardWhenNoMonitoredSelection() {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        manager.selectionMonitor = monitor

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("fallback clipboard text", forType: .string)

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = manager.resolveSynchronousTrigger(frontmostApp: frontmost)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "fallback clipboard text")
        XCTAssertEqual(result?.context.isClipboardFallback, true)
    }

    func testResolveSynchronousTriggerFallsBackToEmptyContextWhenClipboardEmpty() {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        manager.selectionMonitor = monitor

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = manager.resolveSynchronousTrigger(frontmostApp: frontmost)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "")
        XCTAssertEqual(result?.context.isClipboardFallback, false)
    }

    func testHandleTogglePopupTransitionsOpenBarToSearch() {
        let controller = PopupWindowController()
        let manager = HotkeyManager.shared
        manager.setup(popupController: controller)

        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let selection = SelectionContext(
            text: "active selection",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let panel = PopupPanel()
        panel.orderFront(nil)
        controller.panel = panel
        controller.startTestSession(for: selection, initialMode: .actions)
        XCTAssertEqual(controller.modeStore.mode, .actions)

        manager.handleTogglePopup()
        XCTAssertEqual(controller.modeStore.mode, .search)
    }

    func testHandleTogglePopupTogglesOffWhenAlreadyInSearch() {
        let controller = PopupWindowController()
        let manager = HotkeyManager.shared
        manager.setup(popupController: controller)

        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let selection = SelectionContext(
            text: "active selection",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let panel = PopupPanel()
        panel.orderFront(nil)
        controller.panel = panel
        controller.startTestSession(for: selection, initialMode: .search)
        XCTAssertEqual(controller.modeStore.mode, .search)

        manager.handleTogglePopup()
        XCTAssertFalse(controller.isVisible)
    }
}

@MainActor
private final class MockSelectionMonitor: SelectionMonitoring {
    var onSelection: ((SelectionContext, Bool?) -> Void)?
    var latestSelection: (context: SelectionContext, canPaste: Bool?)?
    var clearSelectionCalled = false

    init() {}

    func currentSelection(for bundleID: String?) async -> (context: SelectionContext, canPaste: Bool?)? {
        guard let latest = latestSelection,
              let target = bundleID,
              latest.context.sourceApp.bundleIdentifier == target else {
            return nil
        }
        return latest
    }

    func clearSelection() {
        clearSelectionCalled = true
        latestSelection = nil
    }

    func start() {}
    func stop() {}
}

private struct BoundTestAction: Action {
    let id: String
    let title: String = "Test Bound"
    let icon = ActionIcon.symbol("star")
    let chrome = ActionChrome()
    let onPerform: @MainActor () -> Void

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        onPerform()
        return .success
    }
}

/// `NSRunningApplication` cannot be constructed with an arbitrary bundle ID; the gate only reads
/// `bundleIdentifier`, so a lightweight stand-in keeps the tests hermetic. `triggerAllowed` takes
/// an `NSRunningApplication?`, so the mock subclasses it.
private final class MockFrontmostApp: NSRunningApplication {
    private let bundleID: String?

    init(bundleID: String?) {
        self.bundleID = bundleID
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
}
