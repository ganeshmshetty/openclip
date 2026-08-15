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

    // MARK: - Primary click + can paste → paste

    func testPrimaryClickCanPastePastes() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .primary,
            canPaste: true,
            delivery: .none
        )
        assertCase(result, .paste("hello"))
    }

    // MARK: - Secondary (right-click / shift) always copies

    func testSecondaryCopiesEvenWhenPasteAvailable() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Cannot paste → copy

    func testCannotPasteCopies() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .primary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Non-paste results pass through untouched

    func testCopyStaysCopy() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .copy("hello"),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    func testCutStaysCut() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .cut("hello"),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .cut("hello"))
    }

    func testNonTextResultsPassThrough() {
        let url = URL(string: "https://example.com")!
        let (result, _) = ActionResultDelivery.resolve(
            raw: .openURL(url),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .openURL(url))
    }

    // MARK: - Primary/secondary selection

    func testPrimaryUsesRawResult() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        assertCase(r, .paste("a"))
    }

    func testSecondaryWithoutDeclaredSecondaryCopiesPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .copy("a"))
    }

    func testSecondaryWithNonPastePrimaryStaysPrimary() {
        let (r, _) = ActionResultDelivery.resolve(raw: .openURL(URL(string: "https://x")!), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .openURL(URL(string: "https://x")!))
    }

    func testSecondaryUsesDeclaredSecondary() {
        let d = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: d)
        assertCase(r, .openURL(URL(string: "https://alt")!))
    }

    // MARK: - Probe applies to whichever result is chosen

    func testProbeAppliesToDeclaredPasteSecondary() {
        let d = ActionDelivery(secondary: .paste("a"))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: false, delivery: d)
        assertCase(r, .copy("a"))   // declared paste still downgrades when target can't paste
    }

    func testProbeAppliesToPrimary() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: false, delivery: .none)
        assertCase(r, .copy("a"))
    }

    // MARK: - Toast

    func testDefaultCopiedToastOnDerivedCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        XCTAssertEqual(toast?.message, "Copied")
        XCTAssertEqual(toast?.style, .success)
    }

    func testNoDefaultToastOnHonoredPaste() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertNil(toast)
    }

    func testNoDefaultToastOnNativeCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .copy("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertNil(toast)
    }

    func testDeclaredPrimaryToastOverridesDefault() {
        let t = StatusFeedback(message: "Saved", style: .info)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: ActionDelivery(primaryToast: t))
        XCTAssertEqual(toast, t)
    }

    func testDeclaredSecondaryToastUsed() {
        let t = StatusFeedback(message: "Copied alt", style: .success)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: ActionDelivery(secondaryToast: t))
        XCTAssertEqual(toast, t)
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

    /// Polls `toast.isLoading` until it flips false (the loading toast fades once the action's
    /// result lands) or the deadline passes — a state-based wait instead of a fixed sleep, so the
    /// assertion isn't flaky on slow machines.
    @MainActor
    private func awaitLoadingFade(toast: ToastPanelController) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    private func shownController(resultHandler: ActionResultHandler,
                                 pasteProbe: PasteAvailabilityProbing,
                                 appPolicy: AppPolicyContext,
                                 toastController: ToastPanelController = ToastPanelController()) throws -> PopupWindowController {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let controller = PopupWindowController(resultHandler: resultHandler, pasteProbe: pasteProbe, toastController: toastController)
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
    /// escape hatch silently pastes instead of copying. The policy answers inside the unified
    /// decision (no probe consulted), so the "would happily paste" probe is overridden by the rule.
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

    /// A nil delivery context (an explicit user request, e.g. the AI card's Paste button) must never
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

    // MARK: - Toast routing: paste→copy downgrade shows "Copied"; native copy shows nothing

    /// A `.paste` result downgraded to `.copy` (secondary click / cannot paste) surfaces the
    /// "Copied" toast. The toast is independent of the popup, so it works even though the popup hid.
    @MainActor
    func testDowngradeToCopyShowsCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback?.message, "Copied")
        XCTAssertEqual(toast.currentFeedback?.style, .success)
    }

    /// When resultHandler.handle throws an error, the "Copied" success toast is NOT shown (an error status is shown instead).
    @MainActor
    func testDeliveryFailureDoesNotShowCopiedToast() async throws {
        let handler = FailingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotEqual(toast.currentFeedback?.message, "Copied")
        XCTAssertEqual(toast.currentFeedback?.style, .error)
    }

    /// A native `.copy` result is not a downgrade — it must show no toast.
    @MainActor
    func testNativeCopyShowsNoToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.copy("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertNil(toast.currentFeedback, "native copy must not show the Copied toast")
    }

    /// Every `.showStatus` result routes to the toast (the single status surface). The popup is
    /// shown first (via `shownController`) so `panel` exists and the toast anchors to the popup's
    /// frame — matching production, where a nil panel would otherwise fall back to the cursor.
    @MainActor
    func testShowStatusRoutesToToast() async throws {
        let toast = ToastPanelController()
        let controller = try shownController(resultHandler: RecordingHandler(),
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }
        controller.handleActionResult(.showStatus(StatusFeedback(message: "hello", style: .info)))
        XCTAssertEqual(toast.currentFeedback?.message, "hello")
        XCTAssertTrue(toast.isShowing)
        XCTAssertNotNil(toast.lastAnchorFrame, "status toast must anchor to the popup frame, not the cursor")
    }

    // MARK: - Loading (slow-action) early-close flow

    /// A `showsLoading` action closes the popup immediately, shows a spinner toast, and fades the
    /// toast when the result lands with no description (`.success`).
    @MainActor
    func testLoadingActionShowsSpinnerThenFades() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        await awaitLoadingFade(toast: toast)
        XCTAssertFalse(toast.isLoading, "loading toast should fade once a description-free result lands")
    }

    @MainActor
    private func controllerCurrentContext(_ controller: PopupWindowController) -> ActionContext {
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    /// A `showsLoading` action with an explicit `loadingMessage`; the controller must surface that
    /// message verbatim instead of the "Opening <title>…" default.
    @MainActor
    func testLoadingActionUsesCustomLoadingMessage() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(MessageStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        XCTAssertEqual(toast.currentFeedback?.message, "Connecting to Music…")
        await awaitLoadingFade(toast: toast)
        XCTAssertFalse(toast.isLoading, "loading toast should fade once a description-free result lands")
    }

    // MARK: - Secondary-click threading: runAction must propagate the click intent into the action context

    /// A right-click (secondary click) on an action must reach `perform` as
    /// `context.isSecondaryClick == true`, so Define returns `.copyDefinition` instead of opening
    /// Dictionary.
    @MainActor
    func testRunActionThreadsSecondaryClickIntoActionContext() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: true)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, true, "secondary click must reach the action context")
    }

    /// A normal primary click must reach `perform` as `context.isSecondaryClick == false` (default).
    @MainActor
    func testRunActionDefaultsSecondaryClickToFalse() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: false)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, false, "primary click must not set isSecondaryClick")
    }

    // MARK: - Declared delivery wiring: runAction must snapshot the action's delivery and render its toast

    /// An action declaring a distinct secondary outcome + secondary toast: a secondary (right-click)
    /// perform must deliver the declared secondary and surface the declared toast — the controller
    /// snapshots `action.delivery` and renders the resolved tuple's toast.
    @MainActor
    func testRunActionDeliversDeclaredSecondaryAndToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        let url = URL(string: "https://alt")!
        let declared = StatusFeedback(message: "Copied alt", style: .success)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .openURL(url), secondaryToast: declared))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        XCTAssertEqual(toast.currentFeedback, declared, "the declared secondary toast must surface for a secondary click")
    }

    /// An action declaring a primary toast: a primary perform must surface it even when the result
    /// itself is a description-free `.success` (the toast is not tied to a paste→copy downgrade).
    @MainActor
    func testRunActionShowsDeclaredPrimaryToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        let declared = StatusFeedback(message: "Saved", style: .info)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(primaryToast: declared), performResult: .success)
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: false)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback, declared, "the declared primary toast must surface for a primary click")
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

@MainActor
private final class FailingHandler: ActionResultHandler, Sendable {
    struct TestError: LocalizedError {
        var errorDescription: String? { "Delivery failed" }
    }
    func handle(_ result: ActionResult, in view: NSView?) async throws {
        throw TestError()
    }
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {}
}

private struct FixedProbe: PasteAvailabilityProbing {
    let result: Bool?

    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        result
    }
}

/// A `showsLoading` action whose perform resolves after a short delay to a description-free
/// `.success` (e.g. Apple Music's empty-stdout AppleScript).
private final class SlowStubAction: Action {
    let id = "stub.slow"
    let title = "Slow"
    let icon: ActionIcon = .symbol("play")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .success
    }
}

/// A `showsLoading` action that declares its own loading toast text.
private final class MessageStubAction: Action {
    let id = "stub.message"
    let title = "Slow"
    let icon: ActionIcon = .symbol("play")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true, loadingMessage: "Connecting to Music…") }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .success
    }
}

/// Records the `ActionContext` handed to `perform` so tests can assert the click intent
/// (isSecondaryClick) threaded through the controller's run path. Mutable state lives in a
/// synchronous lock-protected box so the Sendable `Action` conformance stays race-free.
private final class SecondaryClickProbeAction: Action, @unchecked Sendable {
    let id = "stub.secondary"
    let title = "SecondaryClickProbe"
    let icon: ActionIcon = .symbol("hand.point.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let captured = LockedContextBox()
    var lastPerformContext: ActionContext? { captured.value }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        captured.set(context)
        return .copyDefinition(context.selection.text)
    }
}

/// An action carrying a declared `delivery` (secondary outcome + per-click toasts). Its default
/// perform returns a plain `.paste`, so a secondary click derives the declared secondary rather
/// than copying; `performResult` lets tests exercise non-paste results too.
private final class DeclaredDeliveryStub: Action, @unchecked Sendable {
    let id = "stub.declared"
    let title = "Declared"
    let icon: ActionIcon = .symbol("arrow.turn.down.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    var delivery: ActionDelivery? { declaredDelivery }
    private let declaredDelivery: ActionDelivery
    let performResult: ActionResult
    init(delivery: ActionDelivery, performResult: ActionResult = .paste("hello")) {
        self.declaredDelivery = delivery
        self.performResult = performResult
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { performResult }
}

/// Lock-protected capture box for the context an action performed with (synchronous accessors, so
/// it stays callable from an async `perform`).
private final class LockedContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ActionContext?
    func set(_ value: ActionContext) {
        lock.lock(); defer { lock.unlock() }
        storage = value
    }
    var value: ActionContext? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
