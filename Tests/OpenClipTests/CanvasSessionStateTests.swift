import XCTest
import Core

final class CanvasSessionStateTests: XCTestCase {
    func testJSONValueCodableRoundTrip() throws {
        let input: JSONValue = .object([
            "count": .number(2),
            "name": .string("x"),
            "on": .bool(true),
            "nil": .null,
            "list": .array([.number(1), .number(2)])
        ])
        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(input, decoded)
    }

    func testJSONValueConvenience() {
        XCTAssertEqual(JSONValue.number(3).numberValue, 3)
        XCTAssertEqual(JSONValue.string("s").stringValue, "s")
        XCTAssertEqual(JSONValue.bool(true).boolValue, true)
    }

    func testSessionStateSubscriptAndString() {
        var state = CanvasSessionState()
        state["count"] = .number(1)
        state["name"] = .string("a")
        XCTAssertEqual(state["count"], .number(1))
        XCTAssertEqual(state.string("name"), "a")
        XCTAssertNil(state.string("count"))
    }

    func testSessionStateCodableRoundTrip() throws {
        var state = CanvasSessionState()
        state["a"] = .string("v")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CanvasSessionState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testSizeAndHeader() {
        let size = CanvasSize(width: 300, height: 240)
        XCTAssertEqual(size.width, 300)
        let header = CanvasHeader(title: "AI Result", icon: "sparkles")
        XCTAssertEqual(header.title, "AI Result")
        XCTAssertEqual(header.icon, "sparkles")
    }
}
