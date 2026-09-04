import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class MacSelectionMonitorTests: XCTestCase {

    func testCommandATriggersSelectionRetrieval() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x08, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: []))
    }

    // MARK: - Keyboard anchor selection (⌘A popup placement)

    /// Regression: a ⌘A select-all spans the whole document, so anchoring at its top-left corner
    /// flung the popup to the far edge of the content. Select-all must follow the pointer instead.
    func testSelectAllAnchorsNearCursorNotDocumentCorner() {
        let documentBounds = CGRect(x: 40, y: 30, width: 1200, height: 6000) // AX coords, whole doc
        let mouse = CGPoint(x: 900, y: 500)
        XCTAssertEqual(
            MacSelectionMonitor.keyboardAnchor(bounds: documentBounds, isSelectAll: true, mouseLocation: mouse),
            mouse
        )
    }

    /// Arrow-key selections still anchor next to the selected text even when the mouse rests elsewhere.
    func testArrowSelectionAnchorsOnSelectionBounds() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("no screens") }
        // A point guaranteed inside the primary screen in Cocoa coordinates.
        let cocoa = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        // Invert the conversion to synthesize matching AX bounds whose top-left corner maps
        // back to exactly `cocoa`.
        let axY = screen.frame.maxY - cocoa.y
        let bounds = CGRect(x: cocoa.x - 50, y: axY, width: 100, height: 20)
        let mouse = CGPoint(x: 1, y: 1)
        let anchor = MacSelectionMonitor.keyboardAnchor(bounds: bounds, isSelectAll: false, mouseLocation: mouse)
        XCTAssertEqual(anchor.x, cocoa.x - 50, accuracy: 0.5)
        XCTAssertEqual(anchor.y, cocoa.y, accuracy: 0.5)
    }

    /// No retrieval bounds (unsupported app): fall back to the pointer rather than crashing or
    /// anchoring off-screen.
    func testMissingBoundsFallBackToMouseLocation() {
        let mouse = CGPoint(x: 640, y: 400)
        XCTAssertEqual(
            MacSelectionMonitor.keyboardAnchor(bounds: nil, isSelectAll: false, mouseLocation: mouse),
            mouse
        )
    }

    /// An off-screen converted anchor (AX quirks / display changes mid-session) falls back to the
    /// pointer instead of placing the popup nowhere visible.
    func testOffScreenAnchorFallsBackToMouseLocation() {
        let mouse = CGPoint(x: 640, y: 400)
        let offScreenBounds = CGRect(x: -50_000, y: -50_000, width: 100, height: 20)
        XCTAssertEqual(
            MacSelectionMonitor.keyboardAnchor(bounds: offScreenBounds, isSelectAll: false, mouseLocation: mouse),
            mouse
        )
    }

    func testShiftArrowTriggersSelectionRetrieval() {
        for keyCode: UInt16 in [0x7B, 0x7C, 0x7D, 0x7E] {
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.shift]), "keyCode 0x\(String(keyCode, radix: 16))")
        }
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.shift, .command]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7E, flags: [.shift, .option]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7D, flags: [.shift, .option, .command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.shift, .control]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.shift, .control, .command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.control]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.option]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.shift, .command]))
    }

    func testPlainKeysDoNotTrigger() {
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: []))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.shift]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x31, flags: [.command]))
    }

    func testCapsLockDoesNotSilenceTriggers() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.capsLock, .command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x08, flags: [.capsLock, .command]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock, .shift]))
        for keyCode: UInt16 in [0x7C, 0x7D, 0x7E] {
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.capsLock, .shift]), "keyCode 0x\(String(keyCode, radix: 16))")
        }
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock, .shift, .command]))
    }

    func testRapidKeyboardSelectionTriggersCancelPriorPendingTask() {
        let monitor = MacSelectionMonitor()
        
        // First trigger spawns initial debounce task
        monitor.handleSelectionTrigger(isSelectAll: false)
        let firstTask = monitor.debounceTask
        XCTAssertNotNil(firstTask)
        XCTAssertFalse(firstTask?.isCancelled == true)

        // Rapid second trigger immediately cancels prior task and replaces it
        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertTrue(firstTask?.isCancelled == true)
        
        let secondTask = monitor.debounceTask
        XCTAssertNotNil(secondTask)
        XCTAssertFalse(secondTask?.isCancelled == true)

        // Cleanup
        secondTask?.cancel()
    }

    func testStopCancelsAndClearsPendingDebounceTask() {
        let monitor = MacSelectionMonitor()

        monitor.handleSelectionTrigger(isSelectAll: false)
        let task = monitor.debounceTask
        XCTAssertNotNil(task)
        XCTAssertFalse(task?.isCancelled == true)

        monitor.stop()

        XCTAssertTrue(task?.isCancelled == true)
        XCTAssertNil(monitor.debounceTask)
    }

    func testPauseUntilTimestampSuppressesSelectionTriggers() {
        let store = MemorySettingsStore()
        let monitor = MacSelectionMonitor(settingsStore: store)

        // Paused in future
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)

        // Keyboard trigger should be ignored
        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertNil(monitor.debounceTask)

        // Mouse down should be ignored (no hold task spawned)
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertNil(monitor.mouseHoldTask)

        // Mouse up should be ignored (no debounce task spawned)
        monitor.handleMouseUp(app: NSRunningApplication(), cursor: CGPoint(x: 100, y: 100), clickCount: 1)
        XCTAssertNil(monitor.debounceTask)

        // Unpaused
        store.set(.pauseUntilTimestamp, value: 0.0)
        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertNotNil(monitor.debounceTask)
        monitor.debounceTask?.cancel()
    }

    func testStopCancelsPendingMouseHoldTask() {
        let store = MemorySettingsStore()
        store.set(.mouseHoldDuration, value: 0.3)
        let monitor = MacSelectionMonitor(settingsStore: store)

        monitor.start()
        monitor.stop()

        XCTAssertNil(monitor.mouseHoldTask)
    }

    func testDisabledMouseHoldDurationDoesNotSpawnTask() {
        let store = MemorySettingsStore()
        store.set(.mouseHoldDuration, value: 0.0)
        let monitor = MacSelectionMonitor(settingsStore: store)

        monitor.start()
        XCTAssertNil(monitor.mouseHoldTask)
        monitor.stop()
    }

    func testIsMouseHoldEnabledFalseDoesNotSpawnTask() {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        store.set(.mouseHoldDuration, value: 0.3)
        let monitor = MacSelectionMonitor(settingsStore: store)

        monitor.start()
        XCTAssertNil(monitor.mouseHoldTask)
        monitor.stop()
    }

    // MARK: - Hold-to-popup release lifecycle

    @MainActor
    private func makeHoldMonitor() -> MacSelectionMonitor {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: true)
        store.set(.mouseHoldDuration, value: 0.05)
        let monitor = MacSelectionMonitor(settingsStore: store)
        // The test host is OpenClip itself (bundleID matches the com.openclip.* self-exclusion),
        // and RuleEngine.shared would read real user rules (~/.openclip/rules.json) — fix both.
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        // No physical button is pressed in the test host; the hold gesture is simulated.
        monitor.primaryButtonPressed = { true }
        return monitor
    }

    nonisolated private static func runnerApp() -> NSRunningApplication {
        NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)!
    }

    nonisolated private static func fixtureTarget(role: String, selectedText: String?) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: role,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Regression: mouse-up unconditionally cancelled the hold task, so a normal-speed release
    /// landing during the post-timer AX retrieval killed the delivery AND skipped the click path.
    /// A fired hold owns its delivery; release must let it finish.
    @MainActor
    func testReleaseDoesNotCancelFiredHoldDelivery() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 300, y: 300)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }

        // Park retrieval mid-delivery until the test releases it (runs on the AX queue thread).
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: "held text")
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }

        monitor.handleMouseUp(app: Self.runnerApp(), cursor: point, clickCount: 1)

        let task = try XCTUnwrap(monitor.mouseHoldTask)
        XCTAssertFalse(task.isCancelled, "release must not kill a fired hold's in-flight delivery")
        XCTAssertNil(monitor.debounceTask, "a fired hold owns this press; release must not start the click path")

        gate.signal()
        try await waitUntil { delivered != nil }
        XCTAssertEqual(delivered?.text, "held text")
    }

    /// Regression: when the hold timer fired but found nothing to deliver (pause-then-drag-select),
    /// the stuck trigger flag suppressed the same press's real selection on release.
    @MainActor
    func testFiredEmptyHoldFallsThroughToReleasePath() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 120, y: 120)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        // AXButton is rejected by the default gate before any strategy runs (no copy side
        // effects). The gate parks until the test observes the fired flag, so the flag-true
        // window can't be missed by polling.
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXButton", selectedText: "irrelevant")
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })
        // Isolated empty pasteboard so the clipboard fallback can't rescue the hold.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.clearContents()
        monitor.fallbackPasteboard = pasteboard

        monitor.handleMouseDown(at: point)
        let task = try XCTUnwrap(monitor.mouseHoldTask)
        // Two-phase wait: the hold fires (flag true), then bails empty and clears it (flag false).
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { !monitor.triggeredByHold }

        XCTAssertFalse(monitor.triggeredByHold,
                       "a fired hold that exits without delivering must clear its trigger")

        monitor.handleMouseUp(app: Self.runnerApp(), cursor: point, clickCount: 2)
        try await waitUntil { monitor.debounceTask != nil }
        monitor.debounceTask?.cancel()
    }

    /// Regression: dragging past the disarm threshold while a fired-but-unproductive hold still
    /// owned the press left `triggeredByHold` stuck true, so the release path never ran.
    @MainActor
    func testDragBeyondDisarmThresholdClearsStuckHoldFlag() {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 200, y: 200)

        monitor.handleMouseDown(at: point)
        monitor.triggeredByHold = true

        // Sub-threshold movement must not disturb an active hold…
        monitor.handleMouseDragged(at: CGPoint(x: point.x + 2, y: point.y))
        XCTAssertTrue(monitor.triggeredByHold)
        XCTAssertNotNil(monitor.mouseHoldTask)

        // …but crossing the drag threshold hands the gesture back to the release path.
        monitor.handleMouseDragged(at: CGPoint(x: point.x + 50, y: point.y))
        XCTAssertFalse(monitor.triggeredByHold, "drag-in-progress must clear a stuck hold trigger")
        XCTAssertNil(monitor.mouseHoldTask)
    }

    /// Fire-time stationarity gate: only a parked press within the tight fire radius counts;
    /// slow drag starts and already-released presses never fire.
    func testHoldStationarityGate() {
        let down = CGPoint(x: 100, y: 100)

        // ~1.4 px tremor is stationary; 5 px of drift is a drag start.
        XCTAssertTrue(MacSelectionMonitor.holdStationary(
            downPoint: down, pointer: CGPoint(x: 101, y: 101), buttonPressed: true))
        XCTAssertFalse(MacSelectionMonitor.holdStationary(
            downPoint: down, pointer: CGPoint(x: 105, y: 100), buttonPressed: true))

        // A press that already ended must never fire.
        XCTAssertFalse(MacSelectionMonitor.holdStationary(
            downPoint: down, pointer: down, buttonPressed: false))

        // No recorded down point: treat as parked (nothing to drift from).
        XCTAssertTrue(MacSelectionMonitor.holdStationary(
            downPoint: nil, pointer: down, buttonPressed: true))
    }

    // MARK: - Hold-to-trigger cursor & text-target gating

    @MainActor
    func testHoldWithArrowCursorDoesNotFallBackToClipboard() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .arrow }

        // Retriever returns empty (no selection)
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXGroup", selectedText: nil)
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("copied clipboard text", forType: .string)
        monitor.fallbackPasteboard = pasteboard

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { !monitor.triggeredByHold }

        XCTAssertNil(delivered, "Arrow cursor on non-text element must not fall back to clipboard on hold")
    }

    @MainActor
    func testHoldWithBeamCursorFallsBackToClipboardWhenPasteAllowed() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .beam }
        monitor.preparePasteProbe = { _, _ in
            Task { true }
        }

        // Retriever returns empty (no selection in empty text field)
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("text to paste", forType: .string)
        monitor.fallbackPasteboard = pasteboard

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { delivered != nil }

        XCTAssertEqual(delivered?.text, "text to paste")
        XCTAssertTrue(delivered?.isClipboardFallback == true)
    }

    @MainActor
    func testHoldWithBeamCursorDoesNotFallBackToClipboardWhenPasteDenied() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .beam }
        monitor.preparePasteProbe = { _, _ in
            Task { false }
        }

        // Retriever returns empty
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXStaticText", selectedText: nil)
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("clipboard text", forType: .string)
        monitor.fallbackPasteboard = pasteboard

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { !monitor.triggeredByHold }

        XCTAssertNil(delivered, "Beam cursor when paste is denied must not fall back to clipboard on hold")
    }

    @MainActor
    func testHoldWithExistingSelectionDeliversRegardlessOfCursor() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .arrow }

        // Retriever returns active selected text
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: "selected word")
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { delivered != nil }

        XCTAssertEqual(delivered?.text, "selected word")
        XCTAssertFalse(delivered?.isClipboardFallback == true)
    }

    @MainActor
    func testDisabledPolicySuppressesHoldTrigger() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.policyResolver = { _ in AppPolicyContext(disabled: true) }

        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "selected word")
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(delivered, "Hold trigger must not fire when policy is disabled")
    }

    @MainActor
    func testHotkeyOnlyPolicySuppressesHoldTrigger() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.policyResolver = { _ in AppPolicyContext(hotkeyOnly: true) }

        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "selected word")
        }, browserRead: { _ in nil }, copyCapture: { _ in nil })

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(delivered, "Hold trigger must not fire when policy is hotkeyOnly")
    }
}

