import XCTest
import AppKit
import os
@testable import Core
@testable import OpenClip

@MainActor
final class MacSelectionMonitorTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    func testCommandATriggersSelectionRetrieval() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x08, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: []))
    }

    func testKeyboardSelectionInvalidatesCachedInputBeforeDebounce() {
        let monitor = MacSelectionMonitor(settingsStore: MemorySettingsStore())
        let source = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        monitor.latestSelection = (SelectionContext(text: "previous selection", sourceApp: source), true)
        let generation = monitor.selectionGeneration
        defer { monitor.cancelPendingSelection() }

        monitor.handleKeyDown(keyCode: 0x00, flags: [.command])

        XCTAssertNil(monitor.synchronousSelection(for: source), "The instant palette must not reuse input from before a new selection gesture")
        XCTAssertNotEqual(monitor.selectionGeneration, generation)
    }

    /// ⌘L selects the address bar in a browser and the current line in editors — a selection
    /// gesture like any other, and one that produced no popup at all before.
    func testCommandLTriggersSelectionRetrieval() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x25, flags: [.command]))
        XCTAssertTrue(MacSelectionMonitor.isSelectAllKey(keyCode: 0x25, flags: [.command]),
                      "⌘L selects a whole container, so it must be gated like ⌘A")
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x25, flags: []))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x25, flags: [.command, .shift]))
    }

    /// ⇧+Home/End/Page Up/Page Down extend a selection exactly like ⇧+arrow, just by a bigger
    /// stride. They carry `.function` in their modifier flags, which the normalization strips.
    func testShiftJumpKeysExtendSelection() {
        for keyCode: UInt16 in [0x73, 0x77, 0x74, 0x79] {   // home / end / page up / page down
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.shift, .function]),
                          "⇧ + keyCode \(keyCode) must count as extending the selection")
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.shift, .command, .function]))
            XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.function]),
                           "without Shift these only move the caret")
        }
    }

    /// ⌘A is a whole-container gesture; a plain ⌘-something else is not a selection gesture at all.
    func testOnlySelectAllAndLocationAreWholeContainerGestures() {
        XCTAssertTrue(MacSelectionMonitor.isSelectAllKey(keyCode: 0x00, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectAllKey(keyCode: 0x08, flags: [.command]))   // ⌘C
        XCTAssertFalse(MacSelectionMonitor.isSelectAllKey(keyCode: 0x00, flags: [.command, .option]))
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
        let monitor = makeMonitor()
        
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
        let monitor = makeMonitor()

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
        let monitor = makeMonitor(settingsStore: store)

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

    /// While the result card is open the monitor must not read a selection at all: selecting a
    /// word to edit the text under the card used to fire a fresh popup, which replaced the card.
    /// Closing the card (the gate goes false) resumes the ordinary behaviour.
    func testResultCardSuppressesSelectionTriggers() {
        let store = MemorySettingsStore()
        let monitor = makeMonitor(settingsStore: store)
        var cardIsOpen = true
        monitor.isSuppressed = { cardIsOpen }

        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertNil(monitor.debounceTask, "keyboard selection must not trigger while the card is open")

        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertNil(monitor.mouseHoldTask, "hold-to-popup must not arm while the card is open")

        monitor.handleMouseUp(app: NSRunningApplication(), cursor: CGPoint(x: 100, y: 100), clickCount: 2)
        XCTAssertNil(monitor.debounceTask, "double-click selection must not trigger while the card is open")

        cardIsOpen = false
        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertNotNil(monitor.debounceTask, "closing the card must resume selection triggers")
        monitor.debounceTask?.cancel()
    }

    func testStopCancelsPendingMouseHoldTask() {
        let store = MemorySettingsStore()
        store.set(.mouseHoldDuration, value: 0.3)
        let monitor = makeMonitor(settingsStore: store)

        monitor.start()
        monitor.stop()

        XCTAssertNil(monitor.mouseHoldTask)
    }

    func testDisabledMouseHoldDurationDoesNotSpawnTask() {
        let store = MemorySettingsStore()
        store.set(.mouseHoldDuration, value: 0.0)
        let monitor = makeMonitor(settingsStore: store)

        monitor.start()
        XCTAssertNil(monitor.mouseHoldTask)
        monitor.stop()
    }

    func testIsMouseHoldEnabledFalseDoesNotSpawnTask() {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        store.set(.mouseHoldDuration, value: 0.3)
        let monitor = makeMonitor(settingsStore: store)

        monitor.start()
        XCTAssertNil(monitor.mouseHoldTask)
        monitor.stop()
    }

    // MARK: - Hold-to-popup release lifecycle

    private func makeMonitor(settingsStore: SettingsStore = MemorySettingsStore()) -> MacSelectionMonitor {
        let monitor = MacSelectionMonitor(settingsStore: settingsStore)
        monitor.frontmostAppProvider = { MockTestApp(bundleID: "com.apple.TextEdit") }
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in nil }
        return monitor
    }

    @MainActor
    private func makeHoldMonitor() -> MacSelectionMonitor {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: true)
        store.set(.mouseHoldDuration, value: 0.05)
        let monitor = makeMonitor(settingsStore: store)
        // The test host is OpenClip itself (bundleID matches the com.openclip.* self-exclusion),
        // and RuleEngine.shared would read real user rules (~/.openclip/rules.json) — fix both.
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        // No physical button is pressed in the test host; the hold gesture is simulated.
        monitor.primaryButtonPressed = { true }
        return monitor
    }

    nonisolated private static func runnerApp() -> NSRunningApplication {
        MockTestApp(bundleID: Bundle.main.bundleIdentifier, pid: ProcessInfo.processInfo.processIdentifier)
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

    /// A target whose copy strategy is justified by a non-empty `AXSelectedTextRange` while no AX
    /// strategy can read the text itself: the cursor-independent shape of "text is selected, but
    /// only a copy can retrieve it".
    nonisolated private static func copyEvidenceTarget(role: String) -> AXElementInspector.Target {
        var cfRange = CFRange(location: 0, length: 4)
        return AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: role,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: nil,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: AXValueCreate(.cfRange, &cfRange),
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
        }, copyCapture: { _ in nil })

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
        }, copyCapture: { _ in nil })
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
        // Press is over a non-text element.
        monitor.isPressOverEditableText = { _, _ in false }

        // Retriever returns empty (no selection)
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXGroup", selectedText: nil)
        }, copyCapture: { _ in nil })

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

    // MARK: - Structural editability classification

    /// The hit-test resolving to a text control is sufficient on its own.
    func testHitTestTextControlClassifiesAsEditable() {
        XCTAssertTrue(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: true,
            focusedIsEditableControl: false,
            focusedFrame: nil,
            pressAXPoint: CGPoint(x: 100, y: 100)
        ))
    }

    /// Regression: a focused input elsewhere on the page must not admit a hold over read-only text.
    /// The earlier "press and focused field share a web area" rule passed for any page text while
    /// an input held focus, handing unrelated clipboard content to the popup as a selection.
    func testFocusedFieldElsewhereDoesNotAdmitAReadOnlyPress() {
        let focusedInputFrame = CGRect(x: 20, y: 20, width: 200, height: 24)   // a search box
        let pressOverArticle = CGPoint(x: 600, y: 800)                          // page body text

        XCTAssertFalse(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: false,
            focusedIsEditableControl: true,
            focusedFrame: focusedInputFrame,
            pressAXPoint: pressOverArticle
        ))
    }

    /// A focused text control whose frame covers the press is editable — this is what carries web
    /// code editors, whose hidden textarea is IME-anchored at the caret the press just placed.
    func testFocusedFieldFrameCoveringThePressClassifiesAsEditable() {
        let fieldFrame = CGRect(x: 100, y: 100, width: 300, height: 20)

        XCTAssertTrue(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: false,
            focusedIsEditableControl: true,
            focusedFrame: fieldFrame,
            pressAXPoint: CGPoint(x: 150, y: 110)
        ))
        // Just outside the frame, beyond the tolerance: not the field.
        XCTAssertFalse(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: false,
            focusedIsEditableControl: true,
            focusedFrame: fieldFrame,
            pressAXPoint: CGPoint(x: 150, y: 400)
        ))
    }

    /// The tolerance absorbs an editor's caret/textarea offset without swallowing the rest of the
    /// window: a press 8pt outside the field is still the field, one 40pt outside is not.
    func testFocusedFrameToleranceIsBounded() {
        let fieldFrame = CGRect(x: 100, y: 100, width: 300, height: 20)
        let decide: (CGPoint) -> Bool = { point in
            MacSelectionMonitor.pressIsOverEditableText(
                hitIsEditableControl: false,
                focusedIsEditableControl: true,
                focusedFrame: fieldFrame,
                pressAXPoint: point
            )
        }

        XCTAssertTrue(decide(CGPoint(x: 250, y: 128)), "8pt outside the field is within tolerance")
        XCTAssertFalse(decide(CGPoint(x: 250, y: 160)), "40pt outside the field is a different surface")
    }

    /// No focused field and no text control under the press — a window background, toolbar, or
    /// static text — must never inherit the clipboard.
    func testNoEditableSignalAnywhereClassifiesAsNotEditable() {
        XCTAssertFalse(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: false,
            focusedIsEditableControl: false,
            focusedFrame: nil,
            pressAXPoint: CGPoint(x: 100, y: 100)
        ))
    }

    /// A focused element whose frame cannot be read is not treated as covering the press.
    func testMissingFocusedFrameDoesNotAdmitThePress() {
        XCTAssertFalse(MacSelectionMonitor.pressIsOverEditableText(
            hitIsEditableControl: false,
            focusedIsEditableControl: true,
            focusedFrame: nil,
            pressAXPoint: CGPoint(x: 100, y: 100)
        ))
    }

    /// The fallback decision is structural, not cursor-based: the press resolving to an editable
    /// field is what permits the clipboard inheritance (the cursor class is irrelevant here).
    @MainActor
    func testHoldOverEditableFieldFallsBackToClipboardWhenPasteAllowed() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .beam }
        // Press is over the editable field.
        monitor.isPressOverEditableText = { _, _ in true }
        monitor.preparePasteProbe = { _, _ in
            Task { true }
        }

        // Retriever returns empty (no selection in empty text field)
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, copyCapture: { _ in nil })

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

    /// Regression: browsers render an I-beam over *read-only* selectable text (articles, docs), so
    /// the beam alone must never admit the clipboard fallback — a hold over a web page paragraph is
    /// not an editable field. The structural check (`isPressOverEditableText`) is the only signal.
    @MainActor
    func testHoldWithBeamCursorOverReadOnlyTextDoesNotFallBackToClipboard() async throws {        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .beam }
        // The press resolves to static, non-editable content (e.g. a read-only web paragraph).
        monitor.isPressOverEditableText = { _, _ in false }
        monitor.preparePasteProbe = { _, _ in Task { true } }

        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXStaticText", selectedText: nil)
        }, copyCapture: { _ in nil })

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

        XCTAssertNil(delivered, "A beam over read-only text must not paste the clipboard")
    }

    @MainActor
    func testHoldWithUnknownCursorFallsBackToClipboardInEditableFieldWhenPasteAllowed() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .unknown }
        // An unknown cursor over the editable field must still paste: the hit-test, not the cursor,
        // decides.
        monitor.isPressOverEditableText = { _, _ in true }
        monitor.preparePasteProbe = { _, _ in
            Task { true }
        }

        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, copyCapture: { _ in nil })

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("fallback from editable field", forType: .string)
        monitor.fallbackPasteboard = pasteboard

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await waitUntil { monitor.triggeredByHold }
        gate.signal()
        try await waitUntil { delivered != nil }

        XCTAssertEqual(delivered?.text, "fallback from editable field")
        XCTAssertTrue(delivered?.isClipboardFallback == true)
    }


    @MainActor
    func testHoldWithBeamCursorDoesNotFallBackToClipboardWhenPasteDenied() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .beam }
        monitor.isPressOverEditableText = { _, _ in true }
        monitor.preparePasteProbe = { _, _ in
            Task { false }
        }

        // Retriever returns empty
        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXStaticText", selectedText: nil)
        }, copyCapture: { _ in nil })

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

    /// Regression: holding on a window background / toolbar in an app that has an editable field
    /// focused used to paste the clipboard, because the fallback trusted the focused element rather
    /// than the element under the press. The hit-test now anchors it to the press point.
    @MainActor
    func testHoldOnNonTextAreaDoesNotFallBackToClipboard() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .arrow }
        // A text field is focused, but the press is over a non-text area (arrow cursor).
        monitor.isPressOverEditableText = { _, _ in false }
        monitor.preparePasteProbe = { _, _ in Task { true } }

        let gate = DispatchSemaphore(value: 0)
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            gate.wait()
            return Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, copyCapture: { _ in nil })

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

        XCTAssertNil(delivered, "A hold on non-text must not paste the clipboard")
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
        }, copyCapture: { _ in nil })

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
        }, copyCapture: { _ in nil })

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
        }, copyCapture: { _ in nil })

        var delivered: SelectionContext?
        monitor.onSelection = { context, _ in delivered = context }

        monitor.handleMouseDown(at: point)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(delivered, "Hold trigger must not fire when policy is hotkeyOnly")
    }

    @MainActor
    func testShouldSuppressAppScoped() {
        let monitor = makeMonitor()
        var suppressedBundle: String? = "com.apple.Safari"
        var isCardModal = true

        monitor.isSuppressedForApp = { bundleID in
            guard isCardModal, let source = suppressedBundle, let bundleID else { return false }
            return bundleID == source
        }

        XCTAssertTrue(monitor.shouldSuppress(for: "com.apple.Safari"))
        XCTAssertFalse(monitor.shouldSuppress(for: "com.apple.TextEdit"))
        XCTAssertFalse(monitor.shouldSuppress(for: nil))

        isCardModal = false
        XCTAssertFalse(monitor.shouldSuppress(for: "com.apple.Safari"))

        isCardModal = true
        suppressedBundle = nil
        XCTAssertFalse(monitor.shouldSuppress(for: "com.apple.Safari"))
    }

    // MARK: - Monitored Selection Caching & Freshness

    func testLatestSelectionPopulatedOnDelivery() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "cached text")
        }, copyCapture: { _ in nil })

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        let startPoint = CGPoint(x: 100, y: 100)
        let endPoint = CGPoint(x: 200, y: 100) // Drag > 9 px²

        monitor.handleMouseDown(at: startPoint)
        monitor.handleMouseUp(app: app, cursor: endPoint, clickCount: 1)

        try await waitUntil { monitor.latestSelection != nil }

        let cached = try XCTUnwrap(monitor.latestSelection)
        XCTAssertEqual(cached.context.text, "cached text")
        XCTAssertEqual(cached.context.sourceApp.bundleIdentifier, "com.apple.TextEdit")
    }

    func testMouseUpDoesNotStartPasteProbeWhenRetrievalHasNoSelection() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in .default }
        monitor.currentCursorProvider = { .arrow }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, copyCapture: { _ in nil })

        var probeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            probeCalls += 1
            return Task { true }
        }
        var outcome: SelectionTriggerResponse?
        monitor.onReadOutcome = { outcome = $0 }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertEqual(outcome?.status, .noSelection)
        XCTAssertEqual(probeCalls, 0, "A missing selection must not start the Paste menu walk")
    }

    func testMouseUpDoesNotStartPasteProbeWhenCopyIsBlocked() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in .default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXButton", selectedText: nil)
        }, copyCapture: { _ in XCTFail("A gated control must not attempt Copy"); return nil })

        var probeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            probeCalls += 1
            return Task { true }
        }
        var outcome: SelectionTriggerResponse?
        monitor.onReadOutcome = { outcome = $0 }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertEqual(outcome?.status, .copyBlocked)
        XCTAssertEqual(probeCalls, 0, "A blocked retrieval must not start the Paste menu walk")
    }

    func testMouseUpStartsPasteProbeAfterValidSelection() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in .default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "valid selection")
        }, copyCapture: { _ in nil })

        var probeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            probeCalls += 1
            return Task { true }
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertEqual(monitor.latestSelection?.context.text, "valid selection")
        XCTAssertEqual(monitor.latestSelection?.canPaste, true)
        XCTAssertEqual(probeCalls, 1, "A valid selection should still probe Paste availability")
    }

    func testCurrentSelectionReturnsCachedForMatchingBundleAndNilForMismatch() async throws {
        let monitor = makeMonitor()
        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let context = SelectionContext(
            text: "monitored text",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        // Manually set delivered selection by triggering delivery
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "monitored text")
        }, copyCapture: { _ in nil })

        let testApp = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: testApp, cursor: CGPoint(x: 150, y: 100), clickCount: 1)

        try await waitUntil { monitor.latestSelection != nil }

        // Matching bundle ID: returned
        let match = await monitor.currentSelection(for: "com.apple.TextEdit")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.context.text, "monitored text")

        // Mismatched bundle ID: nil
        let mismatch = await monitor.currentSelection(for: "com.apple.Safari")
        XCTAssertNil(mismatch)
    }

    func testCurrentSelectionExpiresAfterMaxAge() async throws {
        let monitor = makeMonitor()
        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let staleContext = SelectionContext(
            text: "stale text",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date().addingTimeInterval(-Constants.selectionMaxAge - 5),
            appPolicy: .default
        )

        // Controllable clock seam
        final class SimulatedClock: @unchecked Sendable {
            var now: Date
            init(now: Date = Date()) { self.now = now }
        }
        let clock = SimulatedClock()
        monitor.now = { clock.now }
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "fresh text")
        }, copyCapture: { _ in nil })

        let testApp = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: testApp, cursor: CGPoint(x: 150, y: 100), clickCount: 1)
        try await waitUntil { monitor.latestSelection != nil }

        // Before expiration: synchronousSelection returns the cached selection
        let initial = monitor.synchronousSelection(for: "com.apple.TextEdit")
        XCTAssertNotNil(initial)
        XCTAssertEqual(initial?.context.text, "fresh text")

        // Advance simulated time past Constants.selectionMaxAge
        clock.now.addTimeInterval(Constants.selectionMaxAge + 1)

        // After expiration: synchronousSelection returns nil and clears the cache
        let expired = monitor.synchronousSelection(for: "com.apple.TextEdit")
        XCTAssertNil(expired, "synchronousSelection must return nil for expired selection")
        XCTAssertNil(monitor.latestSelection, "synchronousSelection must clear latestSelection on expiration")

        // currentSelection also returns nil
        let asyncExpired = await monitor.currentSelection(for: "com.apple.TextEdit")
        XCTAssertNil(asyncExpired, "currentSelection must also return nil for expired selection")
    }

    func testSynchronousSelectionRejectsMismatchedPID() async throws {
        let monitor = makeMonitor()
        let sourceApp = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit", processIdentifier: 1234)
        let context = SelectionContext(
            text: "Hello",
            sourceApp: sourceApp,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        monitor.latestSelection = (context: context, canPaste: true)

        let samePIDApp = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit", processIdentifier: 1234)
        let matched = monitor.synchronousSelection(for: samePIDApp)
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.context.text, "Hello")

        let diffPIDApp = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit", processIdentifier: 5678)
        let mismatched = monitor.synchronousSelection(for: diffPIDApp)
        XCTAssertNil(mismatched)

        let asyncMatched = await monitor.currentSelection(for: samePIDApp)
        XCTAssertNotNil(asyncMatched)
        let asyncMismatched = await monitor.currentSelection(for: diffPIDApp)
        XCTAssertNil(asyncMismatched)
    }

    func testPlainClickClearsLatestSelection() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "selected text")
        }, copyCapture: { _ in nil })

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 150, y: 100), clickCount: 1)
        try await waitUntil { monitor.latestSelection != nil }

        // Plain click (no drag)
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 200))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 200), clickCount: 1)

        XCTAssertNil(monitor.latestSelection, "Plain click must clear latestSelection")
    }

    // MARK: - System chrome gating

    func testWindowMoveResizeOrCloseDoesNotRetrieveOldSelection() async {
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        let changedFrames: [CGRect?] = [frame.offsetBy(dx: 80, dy: 30),
                                       CGRect(x: 100, y: 100, width: 600, height: 400), nil]
        for changedFrame in changedFrames {
            let store = MemorySettingsStore()
            store.set(.isMouseHoldEnabled, value: false)
            let monitor = makeMonitor(settingsStore: store)
            monitor.isSystemChromeAt = { _ in false }
            monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: frame) }
            monitor.windowFrame = { _ in changedFrame }
            monitor.retriever = SelectionRetrievalCoordinator(inspect: {
                XCTFail("Window gestures must be rejected before reading even an old AX selection")
                return Self.fixtureTarget(role: "AXTextField", selectedText: "old selection")
            }, copyCapture: { _ in
                XCTFail("Window gestures must never attempt Copy")
                return nil as Core.TextResult?
            })

            monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
            monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"),
                                  cursor: CGPoint(x: 200, y: 150), clickCount: 1)
            await monitor.debounceTask?.value
            XCTAssertNil(monitor.debounceTask)
            XCTAssertNil(monitor.latestSelection)
        }
    }

    func testMultiClickOnWindowChromeIsRejectedEvenWhenFrameDoesNotChange() async {
        final class SelectionLogSink: LogSink, @unchecked Sendable {
            let messages = OSAllocatedUnfairLock<[String]>(initialState: [])
            func record(date: Date, category: String, level: Core.LogLevel, message: String) {
                if category == "selection" { messages.withLock { $0.append(message) } }
            }
        }
        let previousSinks = Log.currentSinks()
        let logSink = SelectionLogSink()
        Log.addSink(logSink)
        defer { Log.restoreSinks(previousSinks) }
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: frame) }
        monitor.windowFrame = { _ in frame }
        monitor.isPressOnWindowChrome = { _, _ in true }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            XCTFail("A multi-click on window chrome must be rejected before AX retrieval")
            return Self.fixtureTarget(role: "AXTextField", selectedText: "stale selection")
        }, copyCapture: { _ in
            XCTFail("A multi-click on window chrome must not attempt Copy")
            return nil as Core.TextResult?
        })
        var pasteProbeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            pasteProbeCalls += 1
            return Task { true }
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 120, y: 470))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 120, y: 470), clickCount: 2)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection)
        XCTAssertEqual(pasteProbeCalls, 0)
        XCTAssertTrue(
            logSink.messages.withLock { $0 }.contains {
                $0.contains("skipped press on window chrome") && $0.contains("com.apple.TextEdit")
            },
            "A chrome rejection must be diagnosable from the log, not a silent copyBlocked"
        )
    }

    func testMultiClickRejectsWindowChangedAfterMouseUpBeforeSettle() async throws {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let originalFrame = CGRect(x: 100, y: 100, width: 500, height: 400)
        var currentFrame: CGRect? = originalFrame
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: originalFrame) }
        monitor.windowFrame = { _ in currentFrame }
        monitor.isPressOnWindowChrome = { _, _ in false }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            XCTFail("A window changed during the settle interval must be rejected before AX retrieval")
            return Self.fixtureTarget(role: "AXTextField", selectedText: "stale selection")
        }, copyCapture: { _ in
            XCTFail("A window changed during the settle interval must not attempt Copy")
            return nil as Core.TextResult?
        })
        var pasteProbeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            pasteProbeCalls += 1
            return Task { true }
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 200, y: 200))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 200), clickCount: 2)
        let readTask = try XCTUnwrap(monitor.debounceTask)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000)
            currentFrame = nil // closed or otherwise no longer present at the captured window ID
        }
        await readTask.value

        XCTAssertNil(monitor.latestSelection)
        XCTAssertEqual(pasteProbeCalls, 0)
    }

    func testMultiClickInContentWithStableWindowStillRetrievesSelection() async {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: frame) }
        monitor.windowFrame = { _ in frame }
        monitor.isPressOnWindowChrome = { _, _ in false }
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in .default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "content selection")
        }, copyCapture: { _ in nil })
        var pasteProbeCalls = 0
        monitor.preparePasteProbe = { _, _ in
            pasteProbeCalls += 1
            return Task { true }
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        let contentPoint = CGPoint(x: 200, y: 200)
        monitor.handleMouseDown(at: contentPoint)
        monitor.handleMouseUp(app: app, cursor: contentPoint, clickCount: 2)
        await monitor.debounceTask?.value

        XCTAssertEqual(monitor.latestSelection?.context.text, "content selection")
        XCTAssertEqual(monitor.latestSelection?.canPaste, true)
        XCTAssertEqual(pasteProbeCalls, 1)
    }

    nonisolated private static func boundedTarget(selectedText: String, axBounds: CGRect) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil, focusedElement: nil, role: "AXTextField", subRole: nil,
            parentRoles: [], containedInRoles: [], webArea: nil, selectedText: selectedText,
            selectedTextMarkerRange: nil, value: nil, selectedTextRange: nil, bounds: axBounds
        )
    }

    private func makeLocalityMonitor(axBounds: CGRect) -> MacSelectionMonitor {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        monitor.isPressOnWindowChrome = { _, _ in false }
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in .default }
        monitor.currentCursorProvider = { .unknown }
        monitor.preparePasteProbe = { _, _ in Task { true } }
        monitor.gestureScreens = {
            .init(primaryMaxY: 1000, frames: [CGRect(x: 0, y: 0, width: 1440, height: 1000)])
        }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.boundedTarget(selectedText: "1080P", axBounds: axBounds)
        }, copyCapture: { _ in nil })
        return monitor
    }

    /// Issue #162: double-clicking a video made Chromium select a faded-out control label well
    /// below the pointer. A selection that is not under the double-click is not its result.
    func testDoubleClickIgnoresSelectionAwayFromThePointer() async {
        // Cocoa y 80–98, ~100pt below the click at y 200.
        let monitor = makeLocalityMonitor(axBounds: CGRect(x: 16, y: 902, width: 43, height: 18))
        var delivered = 0
        monitor.onSelection = { _, _ in delivered += 1 }

        let point = CGPoint(x: 256, y: 200)
        monitor.handleMouseDown(at: point)
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.bilibili.bilibiliPC"), cursor: point, clickCount: 2)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection)
        XCTAssertEqual(delivered, 0)
    }

    func testDoubleClickDeliversSelectionUnderThePointer() async {
        // Cocoa y 192–210 spans the click.
        let monitor = makeLocalityMonitor(axBounds: CGRect(x: 230, y: 790, width: 60, height: 18))
        let point = CGPoint(x: 256, y: 200)
        monitor.handleMouseDown(at: point)
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"), cursor: point, clickCount: 2)
        await monitor.debounceTask?.value

        XCTAssertEqual(monitor.latestSelection?.context.text, "1080P")
    }

    /// A third press inside the 50 ms geometry settle cancels the double-click read before it
    /// inspects, so an immediate triple-click never reads or presents a word at all.
    func testThirdPressDuringSettleCancelsPendingDoubleClickRead() async {
        let monitor = makeLocalityMonitor(axBounds: CGRect(x: 230, y: 790, width: 60, height: 18))
        final class Counter: @unchecked Sendable { var inspects = 0 }
        let counter = Counter()
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            counter.inspects += 1
            return Self.boundedTarget(selectedText: "word", axBounds: CGRect(x: 230, y: 790, width: 60, height: 18))
        }, copyCapture: { _ in nil })
        var delivered: [String] = []
        monitor.onSelection = { context, _ in delivered.append(context.text) }
        let point = CGPoint(x: 256, y: 200)
        let app = MockTestApp(bundleID: "com.google.Chrome")

        monitor.handleMouseDown(at: point)
        monitor.handleMouseUp(app: app, cursor: point, clickCount: 2)
        let doubleClickRead = monitor.debounceTask
        monitor.handleMouseDown(at: point)
        await doubleClickRead?.value

        XCTAssertEqual(counter.inspects, 0, "the third press must cancel a read that has not started yet")
        XCTAssertTrue(delivered.isEmpty)
    }

    /// A third press that arrives after the word popup has already opened must not lose the
    /// paragraph selection. The paragraph read replaces the word content in place.
    func testThirdClickAfterWordPopupDeliversParagraph() async {
        let bounds = CGRect(x: 230, y: 790, width: 60, height: 18)
        let monitor = makeLocalityMonitor(axBounds: bounds)
        final class TextBox: @unchecked Sendable { var text = "word" }
        let box = TextBox()
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.boundedTarget(selectedText: box.text, axBounds: bounds)
        }, copyCapture: { _ in nil })
        var delivered: [String] = []
        monitor.onSelection = { context, _ in delivered.append(context.text) }
        let point = CGPoint(x: 256, y: 200)
        let app = MockTestApp(bundleID: "com.apple.TextEdit")

        monitor.handleMouseDown(at: point)
        monitor.handleMouseUp(app: app, cursor: point, clickCount: 2)
        // The old 220 ms triple-click wait kept the word popup hidden at this point. A
        // double-click must now present before a plausible third press can arrive.
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(delivered, ["word"])

        box.text = "paragraph text"
        monitor.handleMouseDown(at: point)
        monitor.handleMouseUp(app: app, cursor: point, clickCount: 3)
        await monitor.debounceTask?.value

        XCTAssertEqual(delivered, ["word", "paragraph text"])
        XCTAssertEqual(monitor.latestSelection?.context.text, "paragraph text")
    }

    /// Chromium reports paragraph bounds that miss the click (degenerate 1×1 or offset by a
    /// line). Triple-click selections are not locality-checked, so they still deliver.
    func testTripleClickDeliversDespiteParagraphBoundsAwayFromPointer() async {
        for axBounds in [CGRect(x: 56, y: 955, width: 1, height: 1), CGRect(x: 221, y: 830, width: 717, height: 48)] {
            let monitor = makeLocalityMonitor(axBounds: axBounds)
            let point = CGPoint(x: 411, y: 220)
            monitor.handleMouseDown(at: point)
            monitor.handleMouseUp(app: MockTestApp(bundleID: "com.google.Chrome"), cursor: point, clickCount: 3)
            await monitor.debounceTask?.value
            XCTAssertEqual(monitor.latestSelection?.context.text, "1080P", "\(axBounds)")
        }
    }

    func testDragIgnoresSelectionOutsideTheDragArea() async {
        let monitor = makeLocalityMonitor(axBounds: CGRect(x: 900, y: 100, width: 200, height: 18))
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 500))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"), cursor: CGPoint(x: 300, y: 500), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection)
    }

    func testDragDeliversSelectionAlongTheDragPath() async {
        // Cocoa y 491–509, x 100–300: the dragged line.
        let monitor = makeLocalityMonitor(axBounds: CGRect(x: 100, y: 491, width: 200, height: 18))
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 500))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"), cursor: CGPoint(x: 300, y: 500), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertEqual(monitor.latestSelection?.context.text, "1080P")
    }

    /// Electron needs AXManualAccessibility before its AX tree exists; request it as soon as an
    /// app is activated, and again on press for an app that was already frontmost at launch.
    func testActivationAndPressRequestAppAccessibility() {
        let monitor = makeMonitor()
        let app = MockTestApp(bundleID: "com.anthropic.claudefordesktop", pid: 31337)
        monitor.frontmostAppProvider = { app }
        var requested: [pid_t?] = []
        monitor.requestAppAccessibility = { requested.append($0?.processIdentifier) }

        monitor.handleApplicationActivation(app)
        monitor.handleMouseDown(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(requested, [31337, 31337])
    }

    func testTextDragWithinStationaryWindowStillRetrievesSelection() async {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: frame) }
        monitor.windowFrame = { _ in frame }
        monitor.policyResolver = { _ in .default }
        monitor.currentCursorProvider = { .unknown }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "new selection")
        }, copyCapture: { _ in nil })

        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"),
                              cursor: CGPoint(x: 200, y: 150), clickCount: 1)
        await monitor.debounceTask?.value
        XCTAssertEqual(monitor.latestSelection?.context.text, "new selection")
    }

    func testNewPressIncludingSystemChromeCancelsPendingRetrievalAndHold() {
        for isChrome in [false, true] {
            let store = MemorySettingsStore()
            store.set(.isMouseHoldEnabled, value: false)
            let monitor = makeMonitor(settingsStore: store)
            monitor.isSystemChromeAt = { _ in isChrome }
            let read = Task<Void, Never> { }
            let hold = Task<Void, Never> { }
            monitor.debounceTask = read
            monitor.mouseHoldTask = hold
            monitor.triggeredByHold = true

            monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))

            XCTAssertTrue(read.isCancelled)
            XCTAssertTrue(hold.isCancelled)
            XCTAssertNil(monitor.debounceTask)
            XCTAssertNil(monitor.mouseHoldTask)
            XCTAssertFalse(monitor.triggeredByHold)
        }
    }

    func testApplicationActivationCancelsPendingAutomaticReads() {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        var frontmost: NSRunningApplication = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99991)
        monitor.frontmostAppProvider = { frontmost }
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in nil }
        monitor.start()
        defer { monitor.stop() }
        monitor.handleMouseDown(at: .zero)
        let read = Task<Void, Never> { }
        let hold = Task<Void, Never> { }
        monitor.debounceTask = read
        monitor.mouseHoldTask = hold
        monitor.triggeredByHold = true

        frontmost = MockTestApp(bundleID: "com.apple.Safari", pid: 99992)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: frontmost]
        )

        XCTAssertTrue(read.isCancelled)
        XCTAssertTrue(hold.isCancelled)
        XCTAssertNil(monitor.debounceTask)
        XCTAssertNil(monitor.mouseHoldTask)
        XCTAssertFalse(monitor.triggeredByHold)
    }

    func testSourceAndQueuedApplicationActivationsPreservePendingRead() {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let source = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99991)
        monitor.frontmostAppProvider = { source }
        monitor.handleMouseDown(at: .zero)
        let read = Task<Void, Never> { }
        monitor.debounceTask = read
        defer { monitor.stop() }

        monitor.handleApplicationActivation(source)
        XCTAssertFalse(read.isCancelled, "Activation of the selection source must preserve the read")

        monitor.handleApplicationActivation(MockTestApp(bundleID: "com.apple.Safari", pid: 99992))
        XCTAssertFalse(read.isCancelled, "A queued notification for an app no longer frontmost must be ignored")

        let ownApp = Self.runnerApp()
        monitor.frontmostAppProvider = { ownApp }
        monitor.handleApplicationActivation(ownApp)
        XCTAssertFalse(read.isCancelled, "OpenClip's own popup activation must preserve the selection")
    }

    func testSelectionFinishingAfterAppSwitchIsDiscarded() async throws {
        for keyboard in [false, true] {
            let store = MemorySettingsStore()
            store.set(.isMouseHoldEnabled, value: false)
            let monitor = makeMonitor(settingsStore: store)
            let source = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99991)
            var frontmost: NSRunningApplication = source
            monitor.frontmostAppProvider = { frontmost }
            monitor.policyResolver = { _ in .default }
            monitor.currentCursorProvider = { .unknown }
            monitor.retriever = SelectionRetrievalCoordinator(inspect: {
                Self.fixtureTarget(role: "AXTextField", selectedText: "old selection")
            }, copyCapture: { _ in nil })

            var finishProbe: CheckedContinuation<Bool?, Never>?
            monitor.preparePasteProbe = { _, _ in
                Task { await withCheckedContinuation { finishProbe = $0 } }
            }
            defer { finishProbe?.resume(returning: nil) }
            monitor.onSelection = { _, _ in XCTFail("A completed read must not show over a different app") }

            if keyboard {
                monitor.handleSelectionTrigger(isSelectAll: false)
            } else {
                monitor.handleMouseDown(at: .zero)
                monitor.handleMouseUp(app: source, cursor: CGPoint(x: 100, y: 100), clickCount: 1)
            }
            let read = try XCTUnwrap(monitor.debounceTask)
            try await waitUntil { finishProbe != nil }

            // Same bundle, different process: verify the final guard itself, without an
            // activation notification cancelling the task on its behalf.
            frontmost = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99992)
            finishProbe?.resume(returning: true)
            finishProbe = nil
            await read.value

            XCTAssertNil(monitor.latestSelection, "A stale result must not enter the shortcut cache")
        }
    }

    func testAutomaticCopyRechecksOriginalSourceBeforeCapture() async {
        let store = MemorySettingsStore()
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let source = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99991)
        var frontmost: NSRunningApplication = source
        monitor.frontmostAppProvider = { frontmost }
        monitor.handleMouseDown(at: .zero)
        let request = CopyRequest(trigger: { XCTFail("No synthetic copy should be posted") },
                                  evidence: CopyEvidence("test-selection", .strong))

        for otherApp in [MockTestApp(bundleID: "com.apple.Safari", pid: 99992),
                         MockTestApp(bundleID: "com.apple.TextEdit", pid: 99993),
                         Self.runnerApp()] {
            frontmost = otherApp
            let result = await monitor.captureAutomaticCopy(request) { _ in
                XCTFail("A stale retrieval must be refused before capture touches the clipboard")
                return nil
            }
            XCTAssertNil(result)
        }
    }

    func testHoldEditabilityFinishingAfterAppSwitchDoesNotInheritClipboard() async throws {
        let monitor = makeHoldMonitor()
        let point = CGPoint(x: 100, y: 100)
        let source = MockTestApp(bundleID: "com.apple.TextEdit", pid: 99991)
        var frontmost: NSRunningApplication = source
        monitor.frontmostAppProvider = { frontmost }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .unknown }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: nil)
        }, copyCapture: { _ in nil })
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.setString("clipboard content", forType: .string)
        monitor.fallbackPasteboard = pasteboard

        var finishEditability: CheckedContinuation<Bool, Never>?
        monitor.isPressOverEditableText = { _, pid in
            XCTAssertEqual(pid, source.processIdentifier)
            return await withCheckedContinuation { finishEditability = $0 }
        }
        defer { finishEditability?.resume(returning: false) }
        monitor.onSelection = { _, _ in XCTFail("A stale hold must not show clipboard content in another app") }

        monitor.handleMouseDown(at: point)
        let hold = try XCTUnwrap(monitor.mouseHoldTask)
        try await waitUntil { finishEditability != nil }
        frontmost = MockTestApp(bundleID: "com.apple.Safari", pid: 99992)
        finishEditability?.resume(returning: true)
        finishEditability = nil
        await hold.value

        XCTAssertNil(monitor.latestSelection)
        XCTAssertFalse(monitor.triggeredByHold)
    }

    /// Regression: a drag that starts in a window and overshoots onto the menu bar or Dock — the
    /// normal way of selecting text against a screen edge — was discarded because the *release*
    /// point tested as chrome. Only the press decides whether the interaction is chrome.
    func testDragEndingOverSystemChromeStillSelects() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "edge selection")
        }, copyCapture: { _ in nil })
        // Only the release point (x > 150) would classify as chrome; the press at (100,100) does not.
        monitor.isSystemChromeAt = { $0.x > 150 }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)

        try await waitUntil { monitor.latestSelection != nil }
        XCTAssertEqual(monitor.latestSelection?.context.text, "edge selection")
    }

    /// An interaction that begins on the menu bar or Dock is not a selection and must not trigger.
    func testPressOnSystemChromeIsIgnored() {
        let monitor = makeMonitor()
        monitor.isSystemChromeAt = { _ in true }

        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"),
                              cursor: CGPoint(x: 200, y: 100), clickCount: 1)

        XCTAssertNil(monitor.debounceTask)
        XCTAssertNil(monitor.mouseHoldTask)
    }

    /// A double-click on chrome (e.g. a menu bar item) must not slip past the click-count shortcut.
    func testDoubleClickOnSystemChromeIsIgnored() {
        let monitor = makeMonitor()
        monitor.isSystemChromeAt = { _ in true }

        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"),
                              cursor: CGPoint(x: 100, y: 100), clickCount: 2)

        XCTAssertNil(monitor.debounceTask)
    }

    func testIsSelectionClearingKeyIdentifiesCaretMovementAndTyping() {
        // Navigation keys clear selection
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7B, flags: [])) // Left arrow
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7C, flags: [])) // Right arrow
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7D, flags: [])) // Down arrow
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7E, flags: [])) // Up arrow

        // Plain typing keys clear selection
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x00, flags: [])) // 'a'
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x00, flags: [.shift])) // 'A'
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x0E, flags: [.option])) // ⌥E (dead key / accent)
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x28, flags: [.option, .shift])) // ⌥⇧K ()
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x33, flags: [])) // Delete / Backspace
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x35, flags: [])) // Escape
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x24, flags: [])) // Return
        XCTAssertTrue(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x30, flags: [])) // Tab

        // Selection triggers (Shift + Arrow) should NOT be classified as selection clearing
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7B, flags: [.shift]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x7C, flags: [.shift]))

        // Command and Control shortcuts NEVER clear selection
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x08, flags: [.command])) // ⌘C
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x08, flags: [.command, .option])) // ⌥⌘C
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x00, flags: [.command])) // ⌘A
        XCTAssertFalse(MacSelectionMonitor.isSelectionClearingKey(keyCode: 0x09, flags: [.control])) // ⌃V
    }

    func testSelectionClearingKeyCancelsPendingDebounceTaskAndClearsCache() async throws {
        let monitor = makeMonitor()
        let task: Task<Void, Never> = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return
        }
        monitor.debounceTask = task
        let app = AppIdentity(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let selection = SelectionContext(
            text: "existing text",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        monitor.latestSelection = (context: selection, canPaste: true)

        // User types a character (e.g. keyCode 0x00 'a')
        monitor.handleKeyDown(keyCode: 0x00, flags: [])

        XCTAssertTrue(task.isCancelled, "In-flight debounceTask must be cancelled on selection clearing key")
        XCTAssertNil(monitor.debounceTask, "debounceTask reference must be nil")
        XCTAssertNil(monitor.latestSelection, "latestSelection must be cleared")
    }

    func testHotkeyOnlyPolicySavesSelectionWithoutTriggeringOnSelection() async throws {
        let monitor = makeMonitor()
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext(hotkeyOnly: true) }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "hotkey only selection")
        }, copyCapture: { _ in nil })

        var onSelectionFired = false
        monitor.onSelection = { _, _ in
            onSelectionFired = true
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)

        try await waitUntil { monitor.latestSelection != nil }

        XCTAssertFalse(onSelectionFired, "onSelection must not fire when policy is hotkeyOnly")
        let cached = try XCTUnwrap(monitor.latestSelection)
        XCTAssertEqual(cached.context.text, "hotkey only selection")
    }

    /// Bug #101: "Appear Automatically" is the global form of the per-app `hotkeyOnly` rule — it
    /// suppresses passive auto-show for mouse-release/keyboard selections but must not block the
    /// explicit hold gesture, which is a deliberate request for the popup.
    @MainActor
    func testAppearAutomaticallyDisabledSuppressesAutoShowButNotHold() async throws {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: false)
        store.set(.isMouseHoldEnabled, value: true)
        store.set(.mouseHoldDuration, value: 0.05)
        let monitor = makeMonitor(settingsStore: store)
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext.default }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "selected word")
        }, copyCapture: { _ in nil })

        var popupShown = 0
        monitor.onSelection = { _, _ in popupShown += 1 }

        // Passive drag selection on release: monitoring still runs, but no popup.
        let app = MockTestApp(bundleID: "com.apple.TextEdit")
        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await monitor.debounceTask?.value

        XCTAssertEqual(popupShown, 0, "auto-show must stay off while Appear Automatically is disabled")
        XCTAssertEqual(monitor.latestSelection?.context.text, "selected word",
                       "the selection must still be cached for the hotkey")

        // Explicit hold: still summons the popup with auto-show off.
        let point = CGPoint(x: 150, y: 150)
        monitor.frontmostAppProvider = { Self.runnerApp() }
        monitor.currentMouseLocation = { point }
        monitor.currentCursorProvider = { .arrow }
        monitor.primaryButtonPressed = { true }

        monitor.handleMouseDown(at: point)
        try await waitUntil { popupShown == 1 }
        XCTAssertEqual(popupShown, 1, "the hold gesture must summon the popup with auto-show off")
    }

    // MARK: - Foreign-overlay gate
    // The window-list logic itself lives in OpenSelection's released `CopyTriggerGate`; these pin the
    // macOS-facing decision the monitor relies on.

    func testOverlayGateSuppressesWhenForeignWindowIsOnTop() {
        let selfPID: pid_t = 100
        let frontmost: pid_t = 200
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [
            OnScreenWindowInfo(ownerPID: 999, ownerBundleID: "com.macshot.app", layer: 257, frame: display), // full-screen capture overlay
            OnScreenWindowInfo(ownerPID: frontmost, ownerBundleID: "com.apple.Safari", layer: 0, frame: display)
        ]
        XCTAssertTrue(CopyTriggerGate.isForeignOverlay(
            windows: windows, at: CGPoint(x: 500, y: 400),
            frontmostPID: frontmost, selfPID: selfPID, displayBounds: display))
    }

    /// Regression (NotchNook): an elevated but partial panel from another app is not a capture
    /// overlay and must not suppress the copy-based read.
    func testOverlayGateAllowsWhenForeignWindowIsAPartialPanel() {
        let selfPID: pid_t = 100
        let frontmost: pid_t = 200
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let windows = [
            OnScreenWindowInfo(ownerPID: 999, layer: 25, frame: CGRect(x: 0, y: 707, width: 1470, height: 250)),
            OnScreenWindowInfo(ownerPID: frontmost, layer: 0, frame: display)
        ]
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: windows, at: CGPoint(x: 570, y: 734),
            frontmostPID: frontmost, selfPID: selfPID, displayBounds: display))
    }

    /// Regression: Control Center's invisible (alpha 0) full-height helper window must not count as
    /// a foreign overlay, or copy-only reads on the right of the display would silently stop.
    func testOverlayGateIgnoresInvisibleSystemUIHelper() {
        let selfPID: pid_t = 100
        let frontmost: pid_t = 200
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let windows = [
            OnScreenWindowInfo(ownerPID: 999, ownerBundleID: "com.apple.controlcenter", layer: 22,
                               frame: CGRect(x: 990, y: -11, width: 656, height: 967), alpha: 0.0),
            OnScreenWindowInfo(ownerPID: frontmost, ownerBundleID: "com.apple.Safari", layer: 0, frame: display)
        ]
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: windows, at: CGPoint(x: 1200, y: 400),
            frontmostPID: frontmost, selfPID: selfPID, displayBounds: display))
    }

    func testOverlayGateAllowsWhenFrontmostOwnsTopWindow() {
        let selfPID: pid_t = 100
        let frontmost: pid_t = 200
        let windows = [
            OnScreenWindowInfo(ownerPID: frontmost, layer: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ]
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: windows, at: CGPoint(x: 500, y: 400), frontmostPID: frontmost, selfPID: selfPID))
    }

    /// Our own popup sits above the frontmost app while visible; it must never count as foreign.
    func testOverlayGateIgnoresOwnPopupAboveFrontmostApp() {
        let selfPID: pid_t = 100
        let frontmost: pid_t = 200
        let windows = [
            OnScreenWindowInfo(ownerPID: selfPID, layer: 101, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            OnScreenWindowInfo(ownerPID: frontmost, layer: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ]
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: windows, at: CGPoint(x: 500, y: 400), frontmostPID: frontmost, selfPID: selfPID))
    }

    func testOverlayGateAllowsOnUnknownInputs() {
        let window = OnScreenWindowInfo(ownerPID: 999, layer: 257, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: [window], at: CGPoint(x: 500, y: 500), frontmostPID: 200, selfPID: 100), "no window under the point")
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: [window], at: CGPoint(x: 50, y: 50), frontmostPID: nil, selfPID: 100), "unknown frontmost app")
        XCTAssertFalse(CopyTriggerGate.isForeignOverlay(
            windows: [], at: CGPoint(x: 50, y: 50), frontmostPID: 200, selfPID: 100), "no windows")
    }

    /// Regression (macshot / CleanShot): during a foreign capture overlay the automatic path must
    /// still monitor (so ⌥⌘C stays warm) but must never post the copy retrieval's synthetic ⌘C — it
    /// would land on the overlay's key window, fire its own Copy shortcut, and tear the capture down.
    func testOverlayWithholdsCopyRetrievalButKeepsMonitoring() async throws {
        // A selected range the AX strategies cannot read forces the cascade past AX into the
        // (suppressed) copy tier, without depending on the live cursor class for copy evidence.
        func makeOverlayMonitor(overlay: Bool) -> MacSelectionMonitor {
            let monitor = makeMonitor()
            monitor.isExcludedBundle = { _ in false }
            monitor.policyResolver = { _ in AppPolicyContext.default }
            monitor.isOverlayPresent = { _ in overlay }
            monitor.retriever = SelectionRetrievalCoordinator(
                inspect: { Self.copyEvidenceTarget(role: "AXWebArea") },
                copyCapture: { _ in SelectionResult(text: "from copy", strategy: .keyboardCopy) }
            )
            return monitor
        }

        let app = MockTestApp(bundleID: "com.apple.TextEdit")

        // Overlay present: the copy tier is withheld, so nothing is cached and no popup fires.
        let gated = makeOverlayMonitor(overlay: true)
        gated.onSelection = { _, _ in XCTFail("onSelection must not fire when the copy was withheld") }
        gated.handleMouseDown(at: CGPoint(x: 100, y: 100))
        gated.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await gated.debounceTask?.value
        XCTAssertNil(gated.latestSelection, "the synthetic copy must not run under a foreign overlay")

        // No overlay: the same retrieval reaches the copy tier and caches as usual.
        let ungated = makeOverlayMonitor(overlay: false)
        ungated.handleMouseDown(at: CGPoint(x: 100, y: 100))
        ungated.handleMouseUp(app: app, cursor: CGPoint(x: 200, y: 100), clickCount: 1)
        await ungated.debounceTask?.value
        XCTAssertEqual(ungated.latestSelection?.context.text, "from copy")
    }

    func testTextDragKeepsPressEvidenceWhenReleasedOverBlankSpace() async {
        for releaseCursor: CursorClass in [.arrow, .pointingHand, .unknown, .other] {
            let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.openai.codex", role: "AXGroup")
            var cursor: CursorClass = .beam
            monitor.currentCursorProvider = { cursor }
            final class EvidenceBox: @unchecked Sendable { var value: CopyEvidence? }
            let evidence = EvidenceBox()
            monitor.retriever = SelectionRetrievalCoordinator(
                inspect: { Self.fixtureTarget(role: "AXGroup", selectedText: nil) },
                copyCapture: { request in
                    evidence.value = request.evidence
                    XCTAssertTrue(request.requiresEnabledCopyMenu)
                    return SelectionResult(text: "drag selection", strategy: .keyboardCopy)
                }
            )
            let end = CGPoint(x: 250, y: 150)
            monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
            cursor = releaseCursor
            monitor.handleMouseUp(app: MockTestApp(bundleID: "com.openai.codex"), cursor: end, clickCount: 1)
            await monitor.debounceTask?.value

            XCTAssertEqual(monitor.latestSelection?.context.text, "drag selection", "release cursor: \(releaseCursor)")
            XCTAssertEqual(monitor.latestSelection?.context.cursorPosition, end)
            XCTAssertEqual(evidence.value?.strength, .weak, "A text cursor is context, not proof of a selection")

            // The next gesture starts on a blank/canvas surface and cannot inherit the prior beam.
            // A completed drag is still weak gesture evidence, gated on an enabled Copy command.
            cursor = .arrow
            evidence.value = nil
            monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
            monitor.handleMouseUp(app: MockTestApp(bundleID: "com.openai.codex"), cursor: end, clickCount: 1)
            await monitor.debounceTask?.value
            XCTAssertEqual(evidence.value?.reason, "selection-gesture:dragEnd", "release cursor: \(releaseCursor)")
            XCTAssertEqual(evidence.value?.strength, .weak)
        }
    }

    func testTextDragPressEvidenceDoesNotOverrideObjectSelectionOrOverlayGates() async {
        for (role, overlay) in [("AXImage", false), ("AXCollection", false), ("AXGroup", true)] {
            let monitor = makeKeyboardMonitor(overlay: overlay, bundleID: "com.figma.Desktop", role: role)
            var cursor: CursorClass = .beam
            monitor.currentCursorProvider = { cursor }
            monitor.retriever = SelectionRetrievalCoordinator(
                inspect: { Self.fixtureTarget(role: role, selectedText: nil) },
                copyCapture: { _ in
                    XCTFail("Object selections and overlays must still block automatic Copy")
                    return nil
                }
            )
            monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
            cursor = .arrow
            monitor.handleMouseUp(app: MockTestApp(bundleID: "com.figma.Desktop"), cursor: CGPoint(x: 250, y: 150), clickCount: 1)
            await monitor.debounceTask?.value
            XCTAssertNil(monitor.latestSelection)
        }
    }

    /// Regression: keyboard selection gestures (⌘A / ⌘L / ⇧arrow) are explicit user actions and must
    /// not be blocked by the mouse-oriented copy-evidence gate. The pointer can be an arrow over an
    /// opaque canvas while the keyboard selection is real.
    func testKeyboardSelectionIgnoresCopyEvidenceGate() async {
        let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.figma.Desktop", role: "AXWebArea")

        monitor.handleSelectionTrigger(isSelectAll: false)
        await monitor.debounceTask?.value

        XCTAssertEqual(monitor.latestSelection?.context.text, "from copy")
    }

    /// The foreign-overlay guard still stands on the keyboard path: a capture overlay must never
    /// receive the synthetic ⌘C.
    func testKeyboardSelectionWithholdsCopyUnderForeignOverlay() async {
        let monitor = makeKeyboardMonitor(overlay: true, bundleID: "com.figma.Desktop", role: "AXWebArea")

        monitor.handleSelectionTrigger(isSelectAll: false)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection, "the synthetic copy must not run under a foreign overlay")
    }

    func testKeyboardSelectionWithholdsCopyWhenAutomaticAppearanceIsDisabled() async {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: false)
        let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.figma.Desktop",
                                          role: "AXWebArea", settingsStore: store)
        monitor.retriever = SelectionRetrievalCoordinator(
            inspect: { Self.fixtureTarget(role: "AXWebArea", selectedText: nil) },
            copyCapture: { _ in
                XCTFail("Passive keyboard monitoring must not copy when automatic appearance is disabled")
                return SelectionResult(text: "from copy", strategy: .keyboardCopy)
            }
        )

        monitor.handleSelectionTrigger(isSelectAll: false)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection)
    }

    func testKeyboardSelectionWithholdsCopyUnderHotkeyOnlyPolicy() async {
        let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.figma.Desktop", role: "AXWebArea")
        monitor.policyResolver = { _ in AppPolicyContext(hotkeyOnly: true, retrievalMode: .keyboardCopy) }
        monitor.retriever = SelectionRetrievalCoordinator(
            inspect: { Self.fixtureTarget(role: "AXWebArea", selectedText: nil) },
            copyCapture: { _ in
                XCTFail("Passive keyboard monitoring must not copy under hotkey-only policy")
                return SelectionResult(text: "from copy", strategy: .keyboardCopy)
            }
        )

        monitor.handleSelectionTrigger(isSelectAll: false)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection)
    }

    func testKeyboardSelectionStillCachesNativeTextWithAutomaticCopyDisabled() async {
        for hotkeyOnly in [false, true] {
            let store = MemorySettingsStore()
            store.set(.isAppEnabled, value: hotkeyOnly)
            let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.apple.TextEdit",
                                              role: "AXTextField", settingsStore: store)
            monitor.policyResolver = { _ in AppPolicyContext(hotkeyOnly: hotkeyOnly) }
            monitor.currentCursorProvider = { .unknown }
            monitor.retriever = SelectionRetrievalCoordinator(
                inspect: { Self.fixtureTarget(role: "AXTextField", selectedText: "native selection") },
                copyCapture: { _ in
                    XCTFail("Native selection caching must not copy")
                    return nil as Core.TextResult?
                }
            )
            monitor.onSelection = { _, _ in XCTFail("Passive caching must not show a popup") }

            monitor.handleSelectionTrigger(isSelectAll: false)
            await monitor.debounceTask?.value

            XCTAssertEqual(monitor.latestSelection?.context.text, "native selection")
        }
    }

    /// ⌘A/⌘L on a row/list container is still refused on the keyboard path: opting out of the
    /// copy-evidence gate must not revive the Finder/Mail whole-container copy.
    func testKeyboardSelectAllStillSkippedOnRowContainer() async {
        let monitor = makeKeyboardMonitor(overlay: false, bundleID: "com.apple.finder", role: "AXOutline")

        monitor.handleSelectionTrigger(isSelectAll: true)
        await monitor.debounceTask?.value

        XCTAssertNil(monitor.latestSelection, "⌘A on a row container must not post a synthetic copy")
    }

    func testCancelledTaskDoesNotDeliverSelectionAfterInlineAwait() async {
        let store = MemorySettingsStore()
        store.set(.isAppEnabled, value: true)
        store.set(.isMouseHoldEnabled, value: false)
        let monitor = makeMonitor(settingsStore: store)
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        monitor.isSystemChromeAt = { _ in false }
        monitor.windowAtPoint = { _ in SelectionGestureWindow(id: 123, frame: frame) }
        monitor.windowFrame = { _ in frame }
        monitor.policyResolver = { _ in .default }
        monitor.currentCursorProvider = { .unknown }
        monitor.retriever = SelectionRetrievalCoordinator(inspect: {
            Self.fixtureTarget(role: "AXTextField", selectedText: "first selection")
        }, copyCapture: { _ in nil })

        var deliveredSelections: [String] = []
        monitor.onSelection = { context, _ in
            deliveredSelections.append(context.text)
        }

        monitor.handleMouseDown(at: CGPoint(x: 100, y: 100))
        monitor.handleMouseUp(app: MockTestApp(bundleID: "com.apple.TextEdit"),
                              cursor: CGPoint(x: 200, y: 150), clickCount: 1)

        // Cancel pending selection immediately while task is executing
        monitor.cancelPendingSelection()
        await monitor.debounceTask?.value

        XCTAssertTrue(deliveredSelections.isEmpty, "Cancelled task must never deliver selection to onSelection")
    }

    private func makeKeyboardMonitor(overlay: Bool, bundleID: String, role: String,
                                     settingsStore: SettingsStore = MemorySettingsStore()) -> MacSelectionMonitor {
        let monitor = makeMonitor(settingsStore: settingsStore)
        monitor.isExcludedBundle = { _ in false }
        monitor.policyResolver = { _ in AppPolicyContext(retrievalMode: .keyboardCopy) }
        monitor.frontmostAppProvider = { MockTestApp(bundleID: bundleID) }
        monitor.currentCursorProvider = { .arrow }
        monitor.currentMouseLocation = { CGPoint(x: 300, y: 300) }
        monitor.isOverlayPresent = { _ in overlay }
        monitor.retriever = SelectionRetrievalCoordinator(
            inspect: { Self.fixtureTarget(role: role, selectedText: nil) },
            copyCapture: { _ in SelectionResult(text: "from copy", strategy: .keyboardCopy) }
        )
        return monitor
    }
}

private final class MockTestApp: NSRunningApplication {
    private let bundleID: String?
    private let pid: pid_t

    init(bundleID: String?, pid: pid_t = 99999) {
        self.bundleID = bundleID
        self.pid = pid
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var processIdentifier: pid_t { pid }
}
