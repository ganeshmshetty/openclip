import XCTest
import Core

final class CanvasScriptingTests: XCTestCase {
    func testMountRequestFields() {
        let request = CanvasMountRequest(
            initialState: CanvasSessionState(["a": .string("v")]),
            input: "hello",
            optionValues: ["unit": .string("celsius")],
            preferredSize: CanvasSize(width: 300, height: 240),
            scriptCode: "const ui = () => h('text', {});",
            isAsync: false
        )
        XCTAssertEqual(request.input, "hello")
        XCTAssertEqual(request.initialState.string("a"), "v")
        XCTAssertEqual(request.optionValues, ["unit": .string("celsius")])
        XCTAssertEqual(request.preferredSize?.width, 300)
        XCTAssertEqual(request.scriptCode, "const ui = () => h('text', {});")
        XCTAssertFalse(request.isAsync)
    }

    func testDispatchRequestFields() {
        let event = CanvasEvent(kind: .tap, handler: "increment", value: nil, targetID: "b1")
        let request = CanvasDispatchRequest(event: event, state: CanvasSessionState())
        XCTAssertEqual(request.event.handler, "increment")
    }

    func testResultsAreSendable() {
        let result = CanvasDispatchResult(
            state: CanvasSessionState(["n": .number(1)]),
            tree: .text(CanvasTextProps(content: "hi")),
            effects: [.copy("hi")]
        )
        XCTAssertEqual(result.effects, [.copy("hi")])
        XCTAssertTrue(SendableCheck(result))
    }
}
