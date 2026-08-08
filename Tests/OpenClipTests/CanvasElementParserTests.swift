import XCTest
import Core

private extension JSONValue {
    static func str(_ s: String) -> JSONValue { .string(s) }
    static func num(_ d: Double) -> JSONValue { .number(d) }
    static func bol(_ b: Bool) -> JSONValue { .bool(b) }
}

final class CanvasElementParserTests: XCTestCase {
    private func element(_ type: String, _ props: [String: JSONValue] = [:],
                         _ children: [CanvasElementSpec] = []) -> CanvasElementSpec {
        CanvasElementSpec(type: type, props: props, children: children)
    }

    func testParsesTextNode() throws {
        let spec = element("text", ["content": .str("hello"), "style": .str("title")])
        let tree = try CanvasElementParser.parseTree(spec)
        XCTAssertEqual(tree, .text(CanvasTextProps(content: "hello", style: .title)))
    }

    func testParsesNestedStackWithButton() throws {
        let spec = element("stack", ["orientation": .str("vertical")], [
            element("button", ["title": .str("Go"), "handler": .str("go")]),
            element("text", ["content": .str("bye")])
        ])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .stack(_, let children) = tree else {
            return XCTFail("expected stack, got \(tree)")
        }
        XCTAssertEqual(children.count, 2)
        if case .button(let props) = children[0] {
            XCTAssertEqual(props.title, "Go")
            XCTAssertEqual(props.handler, .dispatch("go"))
        } else {
            XCTFail("expected button, got \(children[0])")
        }
    }

    func testUnknownTypeDropped() throws {
        let spec = element("stack", [:], [
            element("bogus", ["title": .str("x")]),
            element("text", ["content": .str("kept")])
        ])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .stack(_, let children) = tree else {
            return XCTFail("expected stack, got \(tree)")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0], .text(CanvasTextProps(content: "kept")))
    }

    func testMalformedHandlerRendersStatic() throws {
        let spec = element("button", ["title": .str("B"), "handler": .num(3)])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .button(let props) = tree else {
            return XCTFail("expected button, got \(tree)")
        }
        XCTAssertNil(props.handler, "non-string handler renders the node non-interactive")
    }

    func testEffectHandlerObjectParsed() throws {
        let spec = element("button", [
            "title": .str("Copy"),
            "handler": .object(["type": .str("copy"), "text": .str("hi")])
        ])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .button(let props) = tree else {
            return XCTFail("expected button, got \(tree)")
        }
        XCTAssertEqual(props.handler, .effect(.copy("hi")), "a `{type:...}` handler object parses to an effect (H2)")
    }

    func testEffectObjectOpenURLParsed() throws {
        let spec = element("button", [
            "title": .str("Open"),
            "handler": .object(["type": .str("openURL"), "url": .str("https://example.com/a")])
        ])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .button(let props) = tree else {
            return XCTFail("expected button, got \(tree)")
        }
        XCTAssertEqual(props.handler, .effect(.openURL(URL(string: "https://example.com/a")!)))
    }

    func testMalformedEffectObjectRendersStatic() throws {
        let spec = element("button", [
            "title": .str("B"),
            "handler": .object(["type": .str("copy")])   // no `text` → effect can't build → static
        ])
        let tree = try CanvasElementParser.parseTree(spec)
        guard case .button(let props) = tree else {
            return XCTFail("expected button, got \(tree)")
        }
        XCTAssertNil(props.handler, "an unbuildable effect object renders the node non-interactive")
    }

    func testTextFieldWithoutIDDropped() throws {
        let spec = element("textField", ["value": .str("v")])
        XCTAssertThrowsError(try CanvasElementParser.parseTree(spec)) { error in
            XCTAssertTrue(error is CanvasParseError)
        }
    }

    func testTooManyNodesRejects() {
        var children: [CanvasElementSpec] = []
        for _ in 0...CanvasLimits.maxNodes {
            children.append(element("divider"))
        }
        let spec = element("stack", [:], children)
        XCTAssertThrowsError(try CanvasElementParser.parseTree(spec)) { error in
            XCTAssertEqual(error as? CanvasParseError, .tooManyNodes)
        }
    }

    func testTextTooLongRejects() {
        let long = String(repeating: "x", count: CanvasLimits.maxTextLength + 1)
        let spec = element("text", ["content": .str(long)])
        XCTAssertThrowsError(try CanvasElementParser.parseTree(spec)) { error in
            XCTAssertEqual(error as? CanvasParseError, .textTooLong)
        }
    }
}
