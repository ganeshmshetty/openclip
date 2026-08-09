import XCTest
import Core
@testable import OpenClip

/// Records mount/dispatch calls; a gate suspends the fake until released so tests can drive
/// serialization and replacement/cancellation races deterministically.
@MainActor
final class GatedScripting: CanvasScripting {
    struct Call: Equatable {
        let event: CanvasEvent?
        let mount: Bool
    }

    private(set) var calls: [Call] = []
    private(set) var dispatchedStates: [CanvasSessionState] = []   // each request's state snapshot (asserts in-chain freshness)
    var mountResult: CanvasMountResult = CanvasMountResult(state: CanvasSessionState(), tree: .text(CanvasTextProps(content: "hi")))
    var dispatchResults: [CanvasDispatchResult] = []
    var error: Error?

    /// One-shot gate: the first `release()` wakes whatever waiter is suspended on the stream and
    /// opens the gate so later (chain-serialized) waiters never hang on a single yield. All
    /// suspension happens on the MainActor, so the race is deterministic.
    private var gate: AsyncStream<Void>.Continuation?
    private lazy var gateStream: AsyncStream<Void> = AsyncStream { self.gate = $0 }
    private var isOpen = false

    func release() {
        isOpen = true
        gate?.yield()
        gate = nil
    }

    /// Suspends until `release()` unless the gate is already open.
    private func waitForGate() async {
        if !isOpen {
            var iterator = gateStream.makeAsyncIterator()
            await iterator.next()
        }
    }

    func mount(_ request: CanvasMountRequest) async throws -> CanvasMountResult {
        calls.append(Call(event: nil, mount: true))
        await waitForGate()
        if let error { throw error }
        return mountResult
    }

    func dispatch(_ request: CanvasDispatchRequest) async throws -> CanvasDispatchResult {
        calls.append(Call(event: request.event, mount: false))
        dispatchedStates.append(request.state)
        await waitForGate()
        if let error { throw error }
        return dispatchResults.removeFirst()
    }
}

@MainActor
final class CanvasSessionControllerTests: XCTestCase {

    private func makeController() -> (CanvasSessionController, GatedScripting) {
        let scripting = GatedScripting()
        let controller = CanvasSessionController()
        return (controller, scripting)
    }

    private func textTree(_ content: String, id: String? = nil) -> CanvasComponent {
        .text(CanvasTextProps(id: id, content: content))
    }

    /// Arms the controller with a fresh session backed by the given scripting engine.
    private func armSession(_ controller: CanvasSessionController, scripting: (any CanvasScripting)?,
                            tree: CanvasComponent, state: CanvasSessionState = CanvasSessionState()) -> CanvasSession {
        let session = CanvasSession(header: CanvasHeader(title: "t"), input: "selection",
                                    preferredSize: nil, scripting: scripting, isAsync: false,
                                    tree: tree, state: state)
        controller.replace(with: session)
        return session
    }

    /// Lets queued MainActor tasks (the serialized dispatch chain) run to completion.
    private func pump(_ seconds: TimeInterval = 0.05, rounds: Int = 4) {
        for _ in 0..<rounds {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }
    }

    // MARK: - Native (no scripting) sessions

    func testNativeSessionDispatchIsNoop() {
        let controller = CanvasSessionController()
        let tree = textTree("hi", id: "field")
        let session = armSession(controller, scripting: nil, tree: tree, state: CanvasSessionState(["n": .number(0)]))

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "field"))
        pump()

        XCTAssertEqual(controller.session?.id, session.id)
        XCTAssertEqual(controller.session?.tree, tree, "tree must be unchanged")
        XCTAssertEqual(controller.session?.state["n"]?.numberValue, 0, "state must be unchanged")
    }

    // MARK: - Dispatch write-back, effects, serialization

    func testDispatchWritesBackStateAndTree() {
        let (controller, fake) = makeController()
        _ = armSession(controller, scripting: fake, tree: textTree("hi", id: "field"), state: CanvasSessionState(["n": .number(0)]))
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["n": .number(2)]), tree: textTree("2"))]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "field"))
        fake.release()
        pump()

        XCTAssertEqual(controller.session?.state["n"]?.numberValue, 2, "dispatch result must write back state")
        XCTAssertEqual(controller.session?.tree, .text(CanvasTextProps(content: "2")), "dispatch result must write back tree")
    }

    func testDispatchFiresCollectedEffects() {
        let (controller, fake) = makeController()
        let sink = EffectSink()
        _ = armSession(controller, scripting: fake, tree: textTree("hi", id: "field"))
        controller.onEffects = { sink.effects.append($0) }
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("x"), effects: [.paste("x")])]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "field"))
        fake.release()
        pump()

        XCTAssertEqual(sink.effects, [[.paste("x")]], "collected leaf effects must be routed exactly once")
    }

    func testDispatchSerializes() {
        let (controller, fake) = makeController()
        _ = armSession(controller, scripting: fake, tree: textTree("hi", id: "field"))
        fake.dispatchResults = [
            CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("1")),
            CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("2"))
        ]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "first", targetID: "field"))
        controller.dispatch(CanvasEvent(kind: .tap, handler: "second", targetID: "field"))
        pump()   // let the first dispatch hit the gate
        fake.release()
        pump()

        XCTAssertEqual(fake.calls.compactMap { $0.event?.handler }, ["first", "second"],
                       "dispatches must run serially, in enqueue order")
    }

    func testRapidDoubleTapSecondDispatchReadsFreshState() {
        let (controller, fake) = makeController()
        _ = armSession(controller, scripting: fake, tree: textTree("hi", id: "field"), state: CanvasSessionState(["count": .number(0)]))
        fake.dispatchResults = [
            CanvasDispatchResult(state: CanvasSessionState(["count": .number(1)]), tree: textTree("1")),
            CanvasDispatchResult(state: CanvasSessionState(["count": .number(2)]), tree: textTree("2"))
        ]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "inc", targetID: "field"))
        controller.dispatch(CanvasEvent(kind: .tap, handler: "inc", targetID: "field"))
        pump()
        fake.release()
        pump()

        XCTAssertEqual(fake.dispatchedStates.map { $0["count"]?.numberValue }, [0, 1],
                       "each request must snapshot state at execution time, after the prior write-back")
        XCTAssertEqual(controller.session?.state["count"]?.numberValue, 2,
                       "a counter tapped twice must reach 2, not 1")
    }

    // MARK: - Focus restore

    func testSubmitRestoresFocusToTarget() {
        let (controller, fake) = makeController()
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .text(CanvasTextProps(content: "header")),
            .textField(CanvasTextFieldProps(id: "field", value: "", onSubmit: .dispatch("submit")))
        ])
        _ = armSession(controller, scripting: fake, tree: tree)
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: tree)]

        fake.release()
        controller.dispatch(CanvasEvent(kind: .submit, handler: "submit", value: "hello", targetID: "field"))
        pump()

        XCTAssertEqual(controller.session?.focusedComponentID, "field")
    }

    func testBlurChangeSkipsFocusRestore() {
        let (controller, fake) = makeController()
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .textField(CanvasTextFieldProps(id: "field", value: "", onChange: .dispatch("change")))
        ])
        _ = armSession(controller, scripting: fake, tree: tree)
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: tree)]

        fake.release()
        controller.dispatch(CanvasEvent(kind: .change, handler: "change", value: "v", targetID: "field"))
        pump()

        XCTAssertNil(controller.session?.focusedComponentID,
                     "a blur-triggered change must NOT restore focus to the blurring field")
    }

    func testToggleChangeRestoresFocus() {
        let (controller, fake) = makeController()
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .toggle(CanvasToggleProps(id: "tog", value: false, onToggle: .dispatch("toggle")))
        ])
        _ = armSession(controller, scripting: fake, tree: tree)
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["tog": .bool(false)]), tree: tree)]

        fake.release()
        controller.dispatch(CanvasEvent(kind: .change, handler: "toggle", targetID: "tog"))
        pump()

        XCTAssertEqual(controller.session?.focusedComponentID, "tog",
                       "a toggle change keeps focus on the toggle")
    }

    func testToggleFlipsStateBeforeDispatchRequest() {
        let (controller, fake) = makeController()
        let tree = CanvasComponent.toggle(CanvasToggleProps(id: "tog", value: false, onToggle: .dispatch("toggle")))
        _ = armSession(controller, scripting: fake, tree: tree, state: CanvasSessionState(["tog": .bool(false)]))
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["tog": .bool(false)]), tree: tree)]

        fake.release()
        controller.dispatch(CanvasEvent(kind: .change, handler: "toggle", targetID: "tog"))
        pump()

        XCTAssertEqual(fake.dispatchedStates.first?.bool("tog"), true,
                       "the request must carry the post-flip state")
        XCTAssertEqual(controller.session?.state.bool("tog"), false,
                       "write-back overwrites the flipped value with the engine result")
    }

    func testMissingTargetFallsBackToFirstInteractive() {
        let (controller, fake) = makeController()
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .text(CanvasTextProps(content: "static")),
            .textField(CanvasTextFieldProps(id: "new", value: ""))
        ])
        _ = armSession(controller, scripting: fake, tree: tree)
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: tree)]

        fake.release()
        controller.dispatch(CanvasEvent(kind: .submit, handler: "submit", value: "x", targetID: "gone"))
        pump()

        XCTAssertEqual(controller.session?.focusedComponentID, "new",
                       "a vanished target must fall back to the first interactive node")
    }

    // MARK: - Replace / clear / mount

    func testNewMountReplacesSessionAndDiscardsInflight() {
        let (controller, fake) = makeController()
        let headerA = CanvasHeader(title: "A")
        let headerB = CanvasHeader(title: "B")

        controller.mount(CanvasMountRequest(input: "a"), scripting: fake, header: headerA)
        pump()   // let A's mount start and suspend on the gate
        controller.mount(CanvasMountRequest(input: "b"), scripting: fake, header: headerB)
        fake.release()
        pump()

        XCTAssertEqual(fake.calls.filter(\.mount).count, 2, "both mounts must reach the engine")
        XCTAssertEqual(controller.session?.header.title, "B", "the armed session must be B's")
    }

    func testClearCancelsInflightAndLateResultIgnored() {
        let (controller, fake) = makeController()
        let sink = EffectSink()
        let session = armSession(controller, scripting: fake, tree: textTree("hi", id: "field"), state: CanvasSessionState(["n": .number(0)]))
        controller.onEffects = { sink.effects.append($0) }
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["n": .number(9)]), tree: textTree("9"))]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "field"))
        pump()   // let the dispatch start and suspend on the gate
        controller.clear()
        fake.release()
        pump()

        XCTAssertNil(controller.session)
        XCTAssertEqual(session.state["n"]?.numberValue, 0, "a cleared session must never receive the late write-back")
        XCTAssertTrue(sink.effects.isEmpty, "a cleared session must never route effects")
    }

    func testMountArmsSessionAndRequestsFocus() {
        let (controller, fake) = makeController()
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .text(CanvasTextProps(content: "static")),
            .textField(CanvasTextFieldProps(id: "field", value: ""))
        ])
        fake.mountResult = CanvasMountResult(state: CanvasSessionState(["field": .string("")]), tree: tree)

        controller.mount(CanvasMountRequest(input: "selection"), scripting: fake, header: CanvasHeader(title: "t"))
        fake.release()
        pump()

        XCTAssertEqual(controller.session?.header.title, "t")
        XCTAssertEqual(controller.session?.focusedComponentID, "field",
                       "a successful mount must request focus on the first interactive node")
        XCTAssertGreaterThan(controller.session?.focusGeneration ?? 0, 0,
                             "requesting focus must bump the focus generation")
    }

    func testMountErrorSurfacesOnSessionError() {
        let (controller, fake) = makeController()
        struct TestError: Error {}
        fake.error = TestError()
        let sink = EffectSink()

        controller.onSessionError = { sink.errors.append($0) }
        controller.mount(CanvasMountRequest(input: "selection"), scripting: fake, header: CanvasHeader(title: "t"))
        fake.release()
        pump()

        XCTAssertNil(controller.session, "a failed mount must leave no session armed")
        XCTAssertEqual(sink.errors.count, 1, "the mount error must be delivered exactly once")
    }
}

/// @MainActor reference box so a @Sendable `onEffects`/`onSessionError` closure can record calls
/// without capturing a mutable local (illegal under Swift 6 strict concurrency).
@MainActor
private final class EffectSink {
    var effects: [[CanvasEffect]] = []
    var errors: [Error] = []
}
