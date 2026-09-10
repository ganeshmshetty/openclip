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
        XCTAssertEqual(result, "144")
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
        XCTAssertEqual(result, "Fast Result")
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
        XCTAssertEqual(cached, "100")

        let mismatch = evaluator.prewarmedResult(for: calculate.id, textHash: "different".hashValue)
        XCTAssertNil(mismatch)
    }

    func testClearPrewarmedInvalidatesCache() {
        let evaluator = InlineResultEvaluator()
        let calculate = CalculateAction()
        let context = ActionContext(selection: SelectionContext(text: "50 * 2"))

        evaluator.prewarm(actions: [calculate], context: context)
        XCTAssertEqual(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue), "100")

        evaluator.clearPrewarmed()
        XCTAssertNil(evaluator.prewarmedResult(for: calculate.id, textHash: "50 * 2".hashValue))
    }
}
