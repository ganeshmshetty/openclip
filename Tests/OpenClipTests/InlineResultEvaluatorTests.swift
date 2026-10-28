import XCTest
import Core
@testable import OpenClip

@MainActor
final class InlineResultEvaluatorTests: XCTestCase {
    func testInstantSynchronousEvaluationForCalculate() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let context = ActionContext(selection: SelectionContext(text: "12 * 12"))
        
        let result = evaluator.evaluateSynchronous(action: calculate, context: context)
        XCTAssertEqual(result, InlinePreview(text: "144"))
    }

    func testSynchronousEvaluationReturnsNilForNonMathOrNonInline() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let nonMathContext = ActionContext(selection: SelectionContext(text: "not math"))
        XCTAssertNil(evaluator.evaluateSynchronous(action: calculate, context: nonMathContext))

        struct NonInlineAction: Action {
            let id = "test.noninline"
            let title = "Non Inline"
            let icon = ActionIcon.symbol("doc")
            let chrome = ActionChrome(isInlineResult: false)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .text("Done") }
        }

        let nonInline = NonInlineAction()
        let context = ActionContext(selection: SelectionContext(text: "12 * 12"))
        XCTAssertNil(evaluator.evaluateSynchronous(action: nonInline, context: context))
    }

    func testAsynchronousEvaluationAndTimeoutCancellation() async {
        let evaluator = InlineResultEvaluator()
        
        // Mock slow action that takes 800ms
        struct SlowInlineAction: Action {
            let id = "test.slow"
            let title = "Slow Action"
            let icon = ActionIcon.symbol("clock")
            let chrome = ActionChrome(isInlineResult: true)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult {
                try await Task.sleep(nanoseconds: 800_000_000)
                return .text("Too late")
            }
        }
        
        let slowAction = SlowInlineAction()
        let context = ActionContext(selection: SelectionContext(text: "input"))
        
        let result = await evaluator.evaluateAsync(action: slowAction, context: context, timeout: 0.1)
        XCTAssertNil(result, "Exceeding timeout budget must cancel and return nil")
    }

    func testAsynchronousEvaluationSuccess() async {
        let evaluator = InlineResultEvaluator()

        struct FastInlineAction: Action {
            let id = "test.fast"
            let title = "Fast Action"
            let icon = ActionIcon.symbol("bolt")
            let chrome = ActionChrome(isInlineResult: true)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult {
                return .text("Fast Result")
            }
        }

        let fastAction = FastInlineAction()
        let context = ActionContext(selection: SelectionContext(text: "input"))

        let result = await evaluator.evaluateAsync(action: fastAction, context: context, timeout: 0.5)
        XCTAssertEqual(result, InlinePreview(text: "Fast Result"))
    }

    func testInlineJavaScriptReceivesRegexMatchedTextFromLongSelection() async {
        let evaluator = InlineResultEvaluator()
        let selection = "Dhruval @dhruvalgolakiya 23, full time building products. part time code, design, and posting what i’m on. scaled solo dev agency to $200K built - http://appgrowkit.com Trending now"
        let action = JavaScriptAction(
            id: "test.inline-currency",
            title: "Convert Currency",
            scriptCode: "function action(){ return openclip.input.matchedText + '|' + openclip.input.captures[0]; }",
            chrome: ActionChrome(isInlineResult: true),
            optionStore: SettingsActionOptionStore(store: MemorySettingsStore()),
            rules: ExtensionActionRules(requirements: ActionRequirements(regex: #"\$([0-9]+)K?"#))
        )
        let context = ActionContext(selection: SelectionContext(text: selection))

        let result = await evaluator.evaluateAsync(action: action, context: context)

        XCTAssertEqual(result, InlinePreview(text: "$200K|200"))

        let bareAmountContext = ActionContext(selection: SelectionContext(text: "$200"))
        let bareAmountResult = await evaluator.evaluateAsync(action: action, context: bareAmountContext)
        XCTAssertEqual(bareAmountResult, InlinePreview(text: "$200|200"))

        evaluator.prewarm(actions: [action], context: context)
        await evaluator.awaitPrewarmed(timeout: 2.0)
        XCTAssertEqual(
            evaluator.prewarmedResult(for: action, textHash: selection.hashValue),
            InlinePreview(text: "$200K|200"),
            "Prewarming must use the same regex match as click execution"
        )
    }

    func testTextResultPreservesWhitespaceButWhitespaceOnlyIsEmpty() async {
        struct TextInlineAction: Action {
            let id: String
            let title = "Text"
            let icon = ActionIcon.symbol("text.alignleft")
            let chrome = ActionChrome(isInlineResult: true)
            let text: String
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .text(text) }
        }

        let evaluator = InlineResultEvaluator()
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let formatted = "  First line\n    Second line\n"

        let result = await evaluator.evaluateAsync(
            action: TextInlineAction(id: "test.formatted", text: formatted),
            context: context
        )
        let emptyResult = await evaluator.evaluateAsync(
            action: TextInlineAction(id: "test.whitespace", text: " \t\n"),
            context: context
        )

        XCTAssertEqual(result, InlinePreview(text: formatted))
        XCTAssertNil(emptyResult)
    }

    func testNonTerminatingSynchronousJavaScriptTimesOutAndReleasesSlot() async {
        let evaluator = InlineResultEvaluator()
        let javaScriptAction = JavaScriptAction(
            id: "test.infinite-inline",
            title: "Infinite Inline",
            scriptCode: "function action() { while (true) {} }",
            chrome: ActionChrome(isInlineResult: true),
            optionStore: SettingsActionOptionStore(store: MemorySettingsStore())
        )
        let action: any Action = MenuDecoratedAction(
            base: DeliveryDecoratedAction(
                base: KeywordDecoratedAction(base: javaScriptAction, keywords: ["infinite"]),
                delivery: nil
            )
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let initialInFlightCount = OpenClipJSHost.syncEvaluationGate.inFlightCount
        let startedAt = Date()

        let result = await evaluator.evaluateAsync(action: action, context: context, timeout: 0.05)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 1.0, "synchronous JavaScript must be forcibly interrupted")
        XCTAssertEqual(OpenClipJSHost.syncEvaluationGate.inFlightCount, initialInFlightCount)
    }

    func testSessionCancellationAbortsPendingTasks() async {
        let evaluator = InlineResultEvaluator()
        let session = UUID()
        
        struct CancellableAction: Action {
            let id = "test.cancellable"
            let title = "Cancel"
            let icon = ActionIcon.symbol("xmark")
            let chrome = ActionChrome(isInlineResult: true)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult {
                try await Task.sleep(nanoseconds: 500_000_000)
                return .text("Done")
            }
        }
        
        let action = CancellableAction()
        let context = ActionContext(selection: SelectionContext(text: "input"))
        
        evaluator.startEvaluation(action: action, context: context, sessionID: session) { _ in }
        evaluator.cancelSession(session)
        
        XCTAssertNil(evaluator.runningTask(for: action.id, sessionID: session))
    }

    func testPrewarmingCachesSynchronousResult() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let context = ActionContext(selection: SelectionContext(text: "25 + 75"))

        evaluator.prewarm(actions: [calculate], context: context)
        let cached = evaluator.prewarmedResult(for: calculate.id, textHash: "25 + 75".hashValue)
        XCTAssertEqual(cached, InlinePreview(text: "100"))

        let mismatch = evaluator.prewarmedResult(for: calculate.id, textHash: "different".hashValue)
        XCTAssertNil(mismatch)
    }

    func testClearPrewarmedInvalidatesCache() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let context = ActionContext(selection: SelectionContext(text: "50 * 2"))

        evaluator.prewarm(actions: [calculate], context: context)
        XCTAssertEqual(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue), InlinePreview(text: "100"))

        evaluator.clearPrewarmed()
        XCTAssertNil(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue))
    }

    func testEndSessionRetainsWarmCache() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let context = ActionContext(selection: SelectionContext(text: "50 * 2"))

        evaluator.prewarm(actions: [calculate], context: context)
        XCTAssertEqual(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue), InlinePreview(text: "100"))

        // Hiding the popup must keep the warm result so the next selection renders instantly.
        evaluator.endSession(UUID())
        XCTAssertEqual(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue), InlinePreview(text: "100"))

        // Full invalidation still clears it.
        evaluator.clearPrewarmed()
        XCTAssertNil(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue))
    }

    func testStartEvaluationRetriesAfterTransientFailure() async {
        let evaluator = InlineResultEvaluator()

        final class FlakyInlineAction: Action, @unchecked Sendable {
            let id = "test.flaky"
            let title = "Flaky"
            let icon = ActionIcon.symbol("bolt")
            let chrome = ActionChrome(isInlineResult: true)
            private var calls = 0

            @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
            @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
                calls += 1
                return calls == 1 ? .success : .text("Recovered")
            }
        }

        let action = FlakyInlineAction()
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let done = expectation(description: "inline result published")
        var published: InlinePreview?

        evaluator.startEvaluation(action: action, context: context, sessionID: UUID()) { result in
            published = result
            done.fulfill()
        }

        await fulfillment(of: [done], timeout: 3.0)
        XCTAssertEqual(published, InlinePreview(text: "Recovered"), "A nil first result must trigger one retry")
    }

    func testOptionChangeInvalidatesWarmCache() async {
        let evaluator = InlineResultEvaluator()
        let optionStore = SettingsActionOptionStore(store: MemorySettingsStore())
        let option = ExtensionOption(identifier: "suffix", label: "Suffix")

        let action = JavaScriptAction(
            id: "test.option-inline",
            title: "Option Inline",
            scriptCode: "function action(){ return openclip.option('suffix'); }",
            options: [option],
            chrome: ActionChrome(isInlineResult: true),
            optionStore: optionStore
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let hash = "input".hashValue

        optionStore.setStringValue("A", actionID: action.id, option: option)
        evaluator.prewarm(actions: [action], context: context)
        await evaluator.awaitPrewarmed(timeout: 2.0)
        XCTAssertEqual(evaluator.prewarmedResult(for: action, textHash: hash), InlinePreview(text: "A"))

        // Changing the option must invalidate the warmed result, not serve the old "A".
        optionStore.setStringValue("B", actionID: action.id, option: option)
        evaluator.prewarm(actions: [action], context: context)
        await evaluator.awaitPrewarmed(timeout: 2.0)
        XCTAssertEqual(evaluator.prewarmedResult(for: action, textHash: hash), InlinePreview(text: "B"))

        // Even a joined prewarm task must not replay the stale fingerprint's result.
        var published: InlinePreview?
        evaluator.startEvaluation(action: action, context: context, sessionID: UUID()) { published = $0 }
        XCTAssertEqual(published, InlinePreview(text: "B"))
    }
}
