import XCTest
import AppKit
import Core
@testable import OpenClip

final class ActionResultDeliveryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    /// Asserts `result` equals `expected` by pattern matching (ActionResult is not Equatable).
    private func assertCase(_ result: ActionResult, _ expected: ActionResult, file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.paste(let a), .paste(let b)): XCTAssertEqual(a, b, file: file, line: line)
        case (.copy(let a), .copy(let b)): XCTAssertEqual(a, b, file: file, line: line)
        case (.cut(let a), .cut(let b)): XCTAssertEqual(a, b, file: file, line: line)
        case (.openURL(let a), .openURL(let b)): XCTAssertEqual(a, b, file: file, line: line)
        case (.success, .success), (.none, .none): XCTAssertTrue(true, file: file, line: line)
        default: XCTFail("unexpected result \(result)", file: file, line: line)
        }
    }

    // MARK: - Left-click + can paste → paste

    func testLeftClickCanPastePastes() {
        let result = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .leftClick,
            canPaste: true,
            policy: .default
        )
        assertCase(result, .paste("hello"))
    }

    // MARK: - Force-copy (right-click / shift) always copies

    func testForceCopyCopiesEvenWhenPasteAvailable() {
        let result = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .forceCopy,
            canPaste: true,
            policy: .default
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Cannot paste → copy

    func testCannotPasteCopies() {
        let result = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .leftClick,
            canPaste: false,
            policy: .default
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - App policy denyPaste → copy (Terminal/REPL escape hatch)

    func testDenyPasteCopiesEvenWhenPasteAvailable() {
        let policy = AppPolicyContext(denyPaste: true)
        let result = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .leftClick,
            canPaste: true,
            policy: policy
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Non-paste results pass through untouched

    func testCopyStaysCopy() {
        let result = ActionResultDelivery.resolve(
            raw: .copy("hello"),
            clickIntent: .forceCopy,
            canPaste: false,
            policy: .default
        )
        assertCase(result, .copy("hello"))
    }

    func testCutStaysCut() {
        let result = ActionResultDelivery.resolve(
            raw: .cut("hello"),
            clickIntent: .forceCopy,
            canPaste: false,
            policy: .default
        )
        assertCase(result, .cut("hello"))
    }

    func testNonTextResultsPassThrough() {
        let url = URL(string: "https://example.com")!
        let result = ActionResultDelivery.resolve(
            raw: .openURL(url),
            clickIntent: .forceCopy,
            canPaste: false,
            policy: .default
        )
        assertCase(result, .openURL(url))
    }

    // MARK: - RuleEngine propagates denyPaste

    @MainActor
    func testRuleEngineResolvesDenyPaste() {
        RuleEngine.shared.reset()
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.example.terminal"], denyPaste: true))
        let policy = RuleEngine.shared.resolvePolicies(for: "com.example.terminal")
        XCTAssertTrue(policy.denyPaste)
        RuleEngine.shared.reset()
    }

    @MainActor
    func testRuleEngineDefaultDenyPasteIsFalse() {
        RuleEngine.shared.reset()
        let policy = RuleEngine.shared.resolvePolicies(for: "com.example.anything")
        XCTAssertFalse(policy.denyPaste)
    }

    @MainActor
    func testTerminalHasDefaultDenyPaste() {
        RuleEngine.shared.reset()
        let policy = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertTrue(policy.denyPaste)
        let iTermPolicy = RuleEngine.shared.resolvePolicies(for: "com.googlecode.iterm2")
        XCTAssertTrue(iTermPolicy.denyPaste)
    }

    // MARK: - Controller wiring: the delivery inputs must be snapshotted before hide() clears them

    @MainActor
    private func awaitDelivery(from handler: RecordingHandler) async throws -> ActionResult {
        let deadline = Date().addingTimeInterval(3.0)
        while handler.results.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(handler.results.isEmpty, "effect delivery never reached the handler")
        return handler.results.first!
    }

    @MainActor
    private func shownController(resultHandler: ActionResultHandler,
                                 pasteProbe: PasteAvailabilityProbing,
                                 appPolicy: AppPolicyContext) throws -> PopupWindowController {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let controller = PopupWindowController(resultHandler: resultHandler, pasteProbe: pasteProbe)
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: appPolicy
        )
        controller.show(for: context)
        return controller
    }

    /// Regression: a `.paste` result dismisses the popup, and `hide()` clears the live session
    /// context. The denyPaste policy must be captured BEFORE that hide — otherwise the Terminal
    /// escape hatch silently pastes instead of copying.
    @MainActor
    func testDeliverResultAppliesDenyPasteDespiteDismissingHide() async throws {
        let handler = RecordingHandler()
        // Probe would happily paste; the denyPaste policy alone must force a copy.
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: AppPolicyContext(denyPaste: true))
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// A nil delivery context (canvas-explicit effects, e.g. an AI-result Replace button) must never
    /// be re-decided — even when the probe would say paste is unavailable.
    @MainActor
    func testNilDeliveryPassesPasteThroughUntouched() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.handleActionResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    /// Left-click + probe says cannot paste → copy.
    @MainActor
    func testDeliverResultCopiesWhenProbeSaysCannotPaste() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// Left-click + probe says paste is available → paste (positive control through the full wiring).
    @MainActor
    func testDeliverResultPastesWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }
}

/// Records every effect the handler is asked to deliver. @MainActor-isolated, matching the
/// `ActionResultHandler` protocol's main-actor methods.
@MainActor
private final class RecordingHandler: ActionResultHandler, Sendable {
    private(set) var results: [ActionResult] = []

    func handle(_ result: ActionResult, in view: NSView?) async throws {
        results.append(result)
    }

    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {
        results.append(result)
    }
}

private struct FixedProbe: PasteAvailabilityProbing {
    let result: Bool?

    func canPaste(in app: NSRunningApplication?) async -> Bool? {
        result
    }
}
