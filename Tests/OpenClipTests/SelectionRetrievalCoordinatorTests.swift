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
            gate: SelectionGatePolicy(allowedCursors: [.beam], requireSelectionBeforeCopy: true)
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
            gate: SelectionGatePolicy(allowedCursors: [.beam], requireSelectionBeforeCopy: true)
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
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "browser selection", url: "https://example.com") }
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
            browserRead: { _ in BrowserScriptStrategy.BrowserResult(text: "", url: nil) }
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

    func testMenuCopyBlockedWithoutConfirmedSelectionWhenRequired() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .default)  // requireSelectionBeforeCopy
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testMenuCopyProceedsWhenSelectionIsNotRequired() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in "captured via menu copy" }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testMenuCopyCapturesWhenSelectionConfirmed() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "confirmed selection") },
            copyCapture: { _ in "captured copy" }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured copy")
    }

    func testKeyboardCopyCapturesWhenSelectionConfirmed() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "confirmed selection") },
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

    func testCopyCaptureNilReturnsNil() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "confirmed selection") },
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
            inspect: { Self.textFieldTarget(selectedText: "confirmed selection") },
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
}
