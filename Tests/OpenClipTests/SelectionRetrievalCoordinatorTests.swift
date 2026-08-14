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
            browserRead: { _ in nil }
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
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web fallback")
    }

    // MARK: - Copy modes

    func testMenuCopyProceedsWithoutConfirmedSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in "captured via menu copy" }
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
            copyCapture: { _ in "captured via menu copy" }
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
            copyCapture: { _ in "captured keyboard copy" }
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
            copyCapture: { _ in "should not copy rows" }
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
            copyCapture: { _ in "should not copy" }
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
            copyCapture: { _ in "captured select-all text" }
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
            copyCapture: { _ in "copied fallback" }
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
            copyCapture: { _ in "browser copy fallback" }
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
            copyCapture: { _ in "  " }
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
            copyCapture: { _ in "copied text" }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied text")
    }

    func testHungAXInspectTimesOutAndFailsFastWhileOccupied() async {
        let inspectStarted = expectation(description: "inspect started")
        let unblockInspect = expectation(description: "unblock inspect")
        
        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                inspectStarted.fulfill()
                _ = XCTWaiter.wait(for: [unblockInspect], timeout: 0.5)
                return Self.textFieldTarget(selectedText: "eventual text")
            }
        )
        
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        
        // Launch first retrieve that will hang in inspect
        async let firstResult = coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        
        await fulfillment(of: [inspectStarted], timeout: 1.0)
        
        // Second concurrent retrieve should fail fast because axSlot is occupied
        let secondResult = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(secondResult)
        
        unblockInspect.fulfill()
        _ = await firstResult
    }
}

