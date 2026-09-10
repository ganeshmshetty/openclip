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

    func testTimeZoneConverterExtensionInlineEvaluation() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenClipTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let extDir = repoRoot.appendingPathComponent("Extensions/raw/TimeZoneConverter.openclipext")
        let manifestURL = extDir.appendingPathComponent("openclip.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            XCTFail("TimeZoneConverter.openclipext not found at \(manifestURL.path)")
            return
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        XCTAssertEqual(manifest.identifier, "com.openclip.timezone-converter")

        let actionMeta = try XCTUnwrap(manifest.actions.first)
        XCTAssertEqual(actionMeta.inline, true)

        let factory = DefaultActionFactory()
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: extDir, index: 0)
        XCTAssertNotNil(action)
        XCTAssertTrue(action?.chrome.isInlineResult == true)

        let evaluator = InlineResultEvaluator.shared
        let context = ActionContext(selection: SelectionContext(text: "3:00 PM EST"))
        let result = await evaluator.evaluateAsync(action: action!, context: context)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("UTC") == true)
        XCTAssertTrue(result?.contains("7:00 PM") == true)

        // Non-time selection returns nil
        let nonTimeContext = ActionContext(selection: SelectionContext(text: "Hello World"))
        let nonTimeResult = await evaluator.evaluateAsync(action: action!, context: nonTimeContext)
        XCTAssertNil(nonTimeResult)
    }

    func testWordCountExtensionInlineEvaluation() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenClipTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let extDir = repoRoot.appendingPathComponent("Extensions/raw/WordCount.openclipext")
        let manifestURL = extDir.appendingPathComponent("openclip.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            XCTFail("WordCount.openclipext not found at \(manifestURL.path)")
            return
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        XCTAssertEqual(manifest.identifier, "com.openclip.wordcount")
        XCTAssertEqual(manifest.minOpenClipVersion, "1.0.0")

        let actionMeta = try XCTUnwrap(manifest.actions.first)
        XCTAssertEqual(actionMeta.inline, true)

        let factory = DefaultActionFactory()
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: extDir, index: 0)
        XCTAssertNotNil(action)
        XCTAssertTrue(action?.chrome.isInlineResult == true)

        let evaluator = InlineResultEvaluator.shared
        let context = ActionContext(selection: SelectionContext(text: "The quick brown fox jumps"))
        let result = await evaluator.evaluateAsync(action: action!, context: context)
        XCTAssertEqual(result, "5 words")

        let singleContext = ActionContext(selection: SelectionContext(text: "Hello"))
        let singleResult = await evaluator.evaluateAsync(action: action!, context: singleContext)
        XCTAssertEqual(singleResult, "1 word")

        let emptyContext = ActionContext(selection: SelectionContext(text: "   "))
        let emptyResult = await evaluator.evaluateAsync(action: action!, context: emptyContext)
        XCTAssertNil(emptyResult)
    }
}
