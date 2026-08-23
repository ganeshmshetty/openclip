import XCTest
import ApplicationServices
import CoreGraphics
@testable import Core
@testable import OpenClip

final class SelectionRetrievalCoordinatorTests: XCTestCase {

    private static func textFieldTarget(
        selectedText: String? = nil,
        role: String = "AXTextField",
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
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
            bounds: bounds
        )
    }

    private static func webAreaTarget(selectedText: String) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXWebArea",
            subRole: nil,
            parentRoles: ["AXGroup"],
            containedInRoles: ["AXGroup"],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    // MARK: - Gate

    func testGateSkipsButtonRole() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "button text", role: "AXButton") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testUnknownCursorProceedsEvenWhenNotAllowed() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "proceed") }
        )
        let policy = AppPolicyContext(
            retrievalMode: .axTextControl,
            gate: SelectionGatePolicy(allowedCursors: [.beam])
        )
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "proceed")
    }

    func testDisallowedCursorBlocksRetrieval() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "blocked") }
        )
        let policy = AppPolicyContext(
            retrievalMode: .axTextControl,
            gate: SelectionGatePolicy(allowedCursors: [.beam])
        )
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .arrow
        )
        XCTAssertNil(result)
    }

    // MARK: - Modes

    func testAXTextControlReturnsTextFromFixtureTarget() async {
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "hello", bounds: bounds) }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "hello")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testAXWebAreaReturnsTextFromFixtureTarget() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "web text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web text")
    }

    func testAXWebAreaSettleRetryReInspectsUntilTextSettles() async {
        final class InspectCallCount: @unchecked Sendable { var value = 0 }
        let calls = InspectCallCount()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                calls.value += 1
                if calls.value <= 2 {
                    return Self.webAreaTarget(selectedText: "")
                }
                return Self.webAreaTarget(selectedText: "settled web text")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "settled web text")
        XCTAssertGreaterThan(calls.value, 2)
    }

    func testBrowserScriptReturnsBrowserText() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "ignored") },
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "browser selection") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "browser selection")
    }

    func testBrowserScriptNilFallsBackToWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "web fallback") },
            browserRead: { _ in nil },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web fallback")
    }

    func testBrowserScriptEmptyFallsBackToWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "web fallback") },
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "") },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web fallback")
    }

    func testChromiumPatternBundleReachesBrowserReadWithoutEnrichment() async {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "ax text") },
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "js text", html: "<b>js</b> text") },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "captured")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "js text")
        XCTAssertEqual(result?.html, "<b>js</b> text")
        XCTAssertEqual(counter.calls, 0)
    }

    // MARK: - Copy modes

    func testMenuCopyProceedsWithoutConfirmedSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testMenuCopyStartsAtMenuCopyEvenWhenAXTextAvailable() async {
        // A menu-copy rule starts the chain at menu copy, so it never performs the AX text strategy
        // above it — even when the target happens to expose AX text.
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "ax text") },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testKeyboardCopyStartsAtKeyboardCopyEvenWhenAXTextAvailable() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "ax text") },
            copyCapture: { _ in TextResult(text: "captured keyboard copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured keyboard copy")
    }

    func testKeyboardCopyHasNoFallbackBelowIt() async {
        // keyboard-copy is the terminal strategy in the chain, so a failed keyboard copy does not
        // fall through to menu copy.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    func testMenuCopyHasNoFallbackToKeyboardCopy() async {
        // menu-copy is strict for terminals and does not fall through to keyboard-copy, avoiding double timeouts.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.mitchellh.ghostty"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    func testCopyCaptureNilReturnsNil() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testMenuCopyCaptureNilReturnsNil() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    // MARK: - Select-all (⌘A) gating for copy modes

    func testSelectAllMenuCopySkippedOnNonTextElement() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXOutline") },
            copyCapture: { _ in TextResult(text: "should not copy rows") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.finder"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    func testSelectAllMenuCopySkippedOnNonTextElementWithoutSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "row text", role: "AXTable") },
            copyCapture: { _ in TextResult(text: "should not copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.mail"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    func testSelectAllMenuCopyProceedsOnTextElement() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "captured select-all text") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "captured select-all text")
    }

    func testSelectAllDoesNotGateNonCopyModes() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "selected text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "selected text")
    }

    // MARK: - Fallback cascade

    func testAXTextControlFallsBackToCopyWhenAXReadIsEmpty() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "copied fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied fallback")
    }

    func testBrowserScriptFallsBackThroughWebAreaThenCopy() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "") },
            browserRead: { _ in nil },
            copyCapture: { _ in TextResult(text: "browser copy fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "browser copy fallback")
    }

    // MARK: - Blank-text filtering

    func testRetrieveRejectsWhitespaceOnlySelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "   \n  ") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testRetrieveRejectsWhitespaceOnlyCopyCapture() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "  ") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testBlankAXTextFallsThroughToCopyFallback() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "   \t  ") },
            copyCapture: { _ in TextResult(text: "copied text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied text")
    }

    func testStrictlyNativeAppDoesNotFallbackToKeyboardCopy() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected copy")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 0)
    }

    func testNotesResolvesKeyboardCopyFallback() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "copied from notes") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Notes"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied from notes")
    }

    // MARK: - Rich-content enrichment

    func testTextOnlyWebAreaWinEnrichesFromPasteboardCapture() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "plain selection") },
            browserRead: { _ in nil },
            copyCapture: { _ in TextResult(text: "rich selection", html: "<b>rich</b> selection") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "rich selection")
        XCTAssertEqual(result?.html, "<b>rich</b> selection")
    }

    func testNativeAppTextOnlyWinDoesNotFireCopyCapture() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "native text") },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected", html: "<b>unexpected</b>")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "native text")
        XCTAssertNil(result?.html)
        XCTAssertEqual(counter.calls, 0)
    }

    func testRichBrowserWinSkipsEnrichmentCapture() async {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "ax text") },
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "browser text", html: "<i>browser</i> text") },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "captured", html: "<b>captured</b>")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "browser text")
        XCTAssertEqual(result?.html, "<i>browser</i> text")
        XCTAssertEqual(counter.calls, 0)
    }

    func testEnrichmentKeepsOriginalWhenCaptureYieldsNoRichContent() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "plain selection") },
            browserRead: { _ in nil },
            copyCapture: { _ in TextResult(text: "plain capture") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "plain selection")
        XCTAssertNil(result?.html)
    }

    // MARK: - Inspect concurrency gate

    /// Regression: overlapping gestures (quick re-selection, double-click, hotkey+monitor races)
    /// used to fail fast on the single AX slot — popup for neither selection. Each concurrent
    /// read now gets its own permit and delivers independently.
    func testConcurrentRetrievesBothDeliver() async {
        let inspectStarted = expectation(description: "both inspects started")
        inspectStarted.expectedFulfillmentCount = 2
        inspectStarted.assertForOverFulfill = true
        let unblock = DispatchSemaphore(value: 0)

        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                inspectStarted.fulfill()
                unblock.wait()
                return Self.textFieldTarget(selectedText: "overlap text")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        async let firstResult = coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        async let secondResult = coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )

        await fulfillment(of: [inspectStarted], timeout: 2.0)
        unblock.signal()
        unblock.signal()

        let first = await firstResult
        let second = await secondResult
        XCTAssertEqual(first?.text, "overlap text", "first overlapping gesture must still deliver")
        XCTAssertEqual(second?.text, "overlap text", "second overlapping gesture must not be dropped")
    }

    /// Regression: the permit was released only when the underlying blocking inspect returned,
    /// so one slow/hung app kept every subsequent popup missing for seconds. The permit must free
    /// at the caller's watchdog deadline even while that worker is still parked.
    func testInspectPermitFreesAtWatchdogDeadlineWhileWorkerStillHung() async {
        // Worker #1 parks far past axReadTimeout (0.5s): its caller gets nil from the watchdog
        // while the AX queue thread stays blocked on the semaphore.
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer { zombieUnblock.signal() }
        let hungCoordinator = SelectionRetrievalCoordinator(
            inspect: {
                zombieUnblock.wait()
                return Self.textFieldTarget(selectedText: "zombie")
            }
        )
        // A fresh coordinator shares the process-wide gate — proving the permit crossed instances.
        let freshCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        let hungResult = await hungCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(hungResult, "watchdog must return nil for the hung read")

        // The deadline already settled the hung call; a new retrieval must proceed immediately.
        let freshStart = Date()
        let freshResult = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(freshStart), Constants.axReadTimeout,
                          "new read must not wait behind the abandoned hung worker")
        XCTAssertEqual(freshResult?.text, "fresh",
                       "permit must be usable again right after the watchdog deadline")

        zombieUnblock.signal() // release the abandoned AX worker thread
    }

    /// The concurrency cap still bounds pile-up: at `Constants.axMaxConcurrentInspects`
    /// simultaneously-awaited reads, further requests skip instead of stacking more workers.
    func testConcurrencyCapFailsFastWhenSaturated() async {
        let inspectStarted = expectation(description: "cap-filling inspects started")
        inspectStarted.expectedFulfillmentCount = Constants.axMaxConcurrentInspects
        inspectStarted.assertForOverFulfill = true
        let unblock = DispatchSemaphore(value: 0)

        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                inspectStarted.fulfill()
                unblock.wait()
                return Self.textFieldTarget(selectedText: "parked")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        var parkedResults: [Task<TextResult?, Never>] = []
        for _ in 0..<Constants.axMaxConcurrentInspects {
            parkedResults.append(Task {
                await coordinator.retrieve(
                    for: AppIdentity(bundleIdentifier: "com.test.app"),
                    policy: policy,
                    cursor: .unknown
                )
            })
        }
        await fulfillment(of: [inspectStarted], timeout: 2.0)

        let start = Date()
        let overflow = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(overflow, "saturated gate must skip the extra read instead of piling up")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3,
                          "the overflow read must fail fast, not queue")

        unblock.signal()
        for _ in 0..<Constants.axMaxConcurrentInspects { unblock.signal() }
        for task in parkedResults {
            let value = await task.value
            XCTAssertEqual(value?.text, "parked")
        }
    }
}

