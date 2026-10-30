import XCTest
import AppKit
import KeyboardShortcuts
@testable import OpenClip
@testable import Core

/// Hotkey trigger gating: ⌥⌘C obeys Pause, app exclusion, per-app `disabled` rules and the text
/// length contract. "Appear Automatically" does not gate it.
@MainActor
final class HotkeyManagerTests: XCTestCase {
    /// Rules saved by these tests go here, never to the user's real `~/.openclip/rules.json` (#139).
    private var tempRulesURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRulesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-\(UUID().uuidString).json")
        await MainActor.run {
            TestIsolation.reset()
            HotkeyManager.shared.selectionMonitor = nil
            HotkeyManager.shared.retriever = nil
            HotkeyManager.shared.frontmostPIDProvider = { 1001 }
        }
    }

    override func tearDown() async throws {
        HotkeyManager.shared.frontmostPIDProvider = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        HotkeyManager.shared.retriever = nil
        try? FileManager.default.removeItem(at: tempRulesURL)
        try await super.tearDown()
    }

    func testPerActionRetrievalRejectsChangedTargetWithoutRequestedPID() async {
        let manager = HotkeyManager.shared
        manager.frontmostPIDProvider = { 2002 }
        let result = await manager.collectTrigger(frontmostApp: MockFrontmostApp(bundleID: "com.apple.TextEdit"))
        XCTAssertNil(result)
    }

    func testPerActionRetrievalRejectsSwitchDuringFreshRetrieval() async {
        let manager = HotkeyManager.shared
        manager.selectionMonitor = nil
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { manager.frontmostPIDProvider = { 2002 } }
                return Core.TextResult(text: "stale text")
            }
        )
        let result = await manager.collectTrigger(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertNil(result)
    }

    func testStructuredOutcomeExplainsTargetSwitchDuringRetrieval() async {
        let manager = HotkeyManager.shared
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { manager.frontmostPIDProvider = { 2002 } }
                return Core.TextResult(text: "old selection")
            })
        let response = await manager.collectTriggerResponse(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertEqual(response.status, .targetChanged)
        XCTAssertNil(response.context)
    }

    func testFieldChangeDuringReadRejectsLateResult() async {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        manager.selectionMonitor = monitor
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { monitor.clearSelection() }
                return Core.TextResult(text: "old field")
            })
        let response = await manager.collectTriggerResponse(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertEqual(response.status, .targetChanged)
        XCTAssertNil(response.context)
    }

    func testClipboardFallbackRetainsReadFailure() async {
        let manager = HotkeyManager.shared
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(board)
        defer { snapshot.restore(to: board) }
        board.clearContents()
        board.setString("fallback text", forType: .string)
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            detailedCopyCapture: { _ in SelectionReadResponse(status: .copyBlocked) })
        let response = await manager.collectTriggerResponse(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertEqual(response.status, .clipboardFallback)
        XCTAssertEqual(response.retrievalStatus, .copyBlocked)
        XCTAssertEqual(response.context?.text, "fallback text")
    }

    func testHotkeyWaitsForPendingDragReadAndReusesIt() async {
        let manager = HotkeyManager.shared
        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        store.set(.isAppEnabled, value: false)
        let monitor = MacSelectionMonitor(settingsStore: store)
        monitor.frontmostAppProvider = { app }
        monitor.isExcludedBundle = { _ in false }
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in nil }
        monitor.currentCursorProvider = { .unknown }
        monitor.policyResolver = { _ in .default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: { _ in
            Thread.sleep(forTimeInterval: 0.01)
            return AXElementInspector.Target(role: "AXTextField", selectedText: "drag selection")
        }, copyCapture: { _ in XCTFail("AX drag must not post copy"); return nil })
        manager.selectionMonitor = monitor
        manager.retriever = SelectionRetrievalCoordinator(inspect: { _ in
            XCTFail("Pending drag result must be reused"); return AXElementInspector.Target()
        })
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 150), clickCount: 1)
        let response = await manager.collectTriggerResponse(frontmostApp: app)
        XCTAssertEqual(response.status, .selection)
        XCTAssertEqual(response.context?.text, "drag selection")
        XCTAssertEqual(response.context?.selectionGeneration, monitor.selectionGeneration)
    }

    /// "Appear Automatically" off stops the popup following selections; the explicit hotkey must still work.
    func testAutomaticAppearanceOffStillAllowsTheHotkey() {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: false)
        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: app, settingsStore: store))
    }

    func testNoIdentifiableTargetNeverTriggers() {
        // Covers a nil app and a nil bundle ID; neither may fall back to OpenClip itself.
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: nil))
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: MockFrontmostApp(bundleID: nil)))
    }

    func testExcludedAppsNeverTrigger() {
        // A bundle from AppFilter's exclusion list must be rejected even when enabled.
        let excluded = MockFrontmostApp(bundleID: "com.adobe.photoshop")
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: excluded))
    }

    func testAppWithDisabledRuleNeverTriggers() {
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.test.disabled"], disabled: true), saveURL: tempRulesURL)
        let app = MockFrontmostApp(bundleID: "com.test.disabled")
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: app))
    }

    func testAppWithHotkeyOnlyRuleTriggers() {
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.test.hotkeyonly"], hotkeyOnly: true), saveURL: tempRulesURL)
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

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        // Mismatched bundle IDs yield no monitored selection.
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

    /// Issue #74: a clipboard manager dismissing itself can report a nil frontmost app; the hotkey must still fire from the clipboard.
    func testResolveSynchronousTriggerFallsBackToClipboardWhenFrontmostAppIsNil() {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        manager.selectionMonitor = monitor

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard from Paste app", forType: .string)

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: nil)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "clipboard from Paste app")
        XCTAssertEqual(result?.context.isClipboardFallback, true)
        // No identifiable app → sourceApp has nil bundle ID
        XCTAssertNil(result?.context.sourceApp.bundleIdentifier)
    }

    func testResolveSynchronousTriggerFallsBackToEmptyWhenFrontmostAppNilAndClipboardEmpty() {
        let manager = HotkeyManager.shared
        let monitor = MockSelectionMonitor()
        manager.selectionMonitor = monitor

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: nil)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "")
        XCTAssertEqual(result?.context.isClipboardFallback, false)
    }

    func testResolveSynchronousTriggerRespectsGlobalPauseEvenWithNilFrontmostApp() {
        let manager = HotkeyManager.shared
        let store = MemorySettingsStore()
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("should not appear", forType: .string)

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: nil, settingsStore: store)
        XCTAssertNil(trigger)
    }

    func testCollectTriggerRejectsMismatchedRequestedPID() async throws {
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

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit", pid: 99999)
        // With a requestedPID that does not match the actual frontmost app, trigger is refused
        let trigger = await manager.collectTrigger(frontmostApp: frontmost, requestID: nil, requestedPID: 99999)
        XCTAssertNil(trigger)
    }

    func testCollectTriggerRejectsMismatchedRequestID() async throws {
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
        // Random request ID never matches popupTriggerRequestID.
        let trigger = await manager.collectTrigger(frontmostApp: frontmost, requestID: UUID())
        XCTAssertNil(trigger)
    }

    func testHandleActionHotkeyExecutesWhenEnabled() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        let performedExpectation = expectation(description: "Action executed")
        let action = BoundTestAction(id: "test.enabled.hotkey") {
            performedExpectation.fulfill()
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        manager.handleActionHotkey("test.enabled.hotkey", settingsStore: store)
        await fulfillment(of: [performedExpectation], timeout: 2.0)
    }

    func testHandleActionHotkeyRejectsDisabledAction() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let action = BoundTestAction(id: "test.disabled.hotkey") {
            performed = true
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledActionIDs, value: ["test.disabled.hotkey"])

        manager.handleActionHotkey("test.disabled.hotkey", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testHandleActionHotkeyRejectsDisabledPackage() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let action = BoundTestAction(
            id: "pkg123.action",
            chrome: ActionChrome(source: .extensionPkg(packageID: "pkg123"))
        ) {
            performed = true
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledPackages, value: ["pkg123"])

        manager.handleActionHotkey("pkg123.action", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testHandleActionHotkeyRejectsDisabledExtensionGroupParent() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let parentGroup = BoundTestAction(
            id: "pkg123.group",
            chrome: ActionChrome(popupBehavior: .showSubActions)
        ) {}
        let childAction = BoundTestAction(
            id: "pkg123.group.child",
            chrome: ActionChrome()
        ) {
            performed = true
        }
        ActionCoordinator.shared.register(action: parentGroup)
        ActionCoordinator.shared.register(action: childAction)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledActionIDs, value: ["pkg123.group"])

        manager.handleActionHotkey("pkg123.group.child", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testCollectTriggerPreservesCompletePayloadInCachedPath() async throws {
        let manager = HotkeyManager.shared
        let mockMonitor = MockSelectionMonitor()
        manager.selectionMonitor = mockMonitor

        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let sourceApp = AppIdentity(app)
        let sampleFlavors = [RichPasteboardFlavor(type: "public.utf8-plain-text", data: Data("Cached sample text".utf8))]
        let context = SelectionContext(
            text: "Cached sample text",
            sourceApp: sourceApp,
            cursorPosition: CGPoint(x: 100, y: 100),
            mouseDownLocation: CGPoint(x: 90, y: 90),
            selectionBounds: CGRect(x: 10, y: 20, width: 100, height: 30),
            timestamp: Date(),
            appPolicy: .default,
            isClipboardFallback: false,
            html: "<p>Cached sample text</p>",
            rtf: "{\\rtf1 Cached sample text}",
            flavors: sampleFlavors
        )
        mockMonitor.latestSelection = (context: context, canPaste: true)

        let trigger = await manager.collectTrigger(frontmostApp: app)
        let resolved = try XCTUnwrap(trigger)
        XCTAssertEqual(resolved.context.text, "Cached sample text")
        XCTAssertEqual(resolved.context.html, "<p>Cached sample text</p>")
        XCTAssertEqual(resolved.context.rtf, "{\\rtf1 Cached sample text}")
        XCTAssertEqual(resolved.context.flavors, sampleFlavors)
    }

    func testResolveSynchronousTriggerPreservesCompletePayloadInCachedPath() throws {
        let manager = HotkeyManager.shared
        let mockMonitor = MockSelectionMonitor()
        manager.selectionMonitor = mockMonitor

        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let sourceApp = AppIdentity(app)
        let sampleFlavors = [RichPasteboardFlavor(type: "public.utf8-plain-text", data: Data("Sync sample text".utf8))]
        let context = SelectionContext(
            text: "Sync sample text",
            sourceApp: sourceApp,
            cursorPosition: CGPoint(x: 100, y: 100),
            mouseDownLocation: CGPoint(x: 90, y: 90),
            selectionBounds: CGRect(x: 10, y: 20, width: 100, height: 30),
            timestamp: Date(),
            appPolicy: .default,
            isClipboardFallback: false,
            html: "<p>Sync sample text</p>",
            rtf: "{\\rtf1 Sync sample text}",
            flavors: sampleFlavors
        )
        mockMonitor.latestSelection = (context: context, canPaste: true)

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: app)
        let resolved = try XCTUnwrap(trigger)
        XCTAssertEqual(resolved.context.text, "Sync sample text")
        XCTAssertEqual(resolved.context.html, "<p>Sync sample text</p>")
        XCTAssertEqual(resolved.context.rtf, "{\\rtf1 Sync sample text}")
        XCTAssertEqual(resolved.context.flavors, sampleFlavors)
    }

    func testCollectTriggerPreservesCompletePayloadInFreshPath() async throws {
        let manager = HotkeyManager.shared
        manager.selectionMonitor = nil

        let app = MockFrontmostApp(bundleID: "com.sublimetext.4")
        let sampleFlavors = [
            RichPasteboardFlavor(type: "public.html", data: Data("<p>Fresh text</p>".utf8)),
            RichPasteboardFlavor(type: "com.apple.custom", data: Data([10, 20, 30]))
        ]

        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in
                AXElementInspector.Target()
            },
            copyCapture: { _ in
                Core.TextResult(
                    text: "Fresh text",
                    bounds: CGRect(x: 10, y: 20, width: 30, height: 40),
                    html: "<p>Fresh text</p>",
                    rtf: "{\\rtf1 Fresh text}",
                    flavors: sampleFlavors
                )
            }
        )

        let trigger = await manager.collectTrigger(frontmostApp: app)
        let resolved = try XCTUnwrap(trigger)
        XCTAssertEqual(resolved.context.text, "Fresh text")
        XCTAssertEqual(resolved.context.html, "<p>Fresh text</p>")
        XCTAssertEqual(resolved.context.rtf, "{\\rtf1 Fresh text}")
        XCTAssertEqual(resolved.context.flavors, sampleFlavors)
    }
}


@MainActor
private final class MockSelectionMonitor: SelectionMonitoring {
    var onSelection: ((SelectionContext, Bool?) -> Void)?
    var latestSelection: (context: SelectionContext, canPaste: Bool?)?
    var selectionGeneration: UInt64? = 0
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
        selectionGeneration = (selectionGeneration ?? 0) &+ 1
        clearSelectionCalled = true
        latestSelection = nil
    }

    func start() {}
    func stop() {}
}

private struct BoundTestAction: Action {
    let id: String
    var title: String = "Test Bound"
    var icon = ActionIcon.symbol("star")
    var chrome: ActionChrome = ActionChrome()
    let onPerform: @MainActor () -> Void

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        onPerform()
        return .success
    }
}

/// `NSRunningApplication` can't take an arbitrary bundle ID, so this stand-in subclasses it for hermetic tests.
private final class MockFrontmostApp: NSRunningApplication {
    private let bundleID: String?
    private let pid: pid_t

    init(bundleID: String?, pid: pid_t = 1001) {
        self.bundleID = bundleID
        self.pid = pid
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var processIdentifier: pid_t { pid }
}
