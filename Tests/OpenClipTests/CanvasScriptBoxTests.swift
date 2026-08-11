// CanvasScriptBoxTests.swift
// OpenClipTests
//

import XCTest
import JavaScriptCore
@testable import Core
@testable import OpenClip

final class CanvasScriptBoxTests: XCTestCase {
    func testHBuildsElementObjects() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let value = try XCTUnwrap(context.evaluateScript("h('text', { content: 'hello', id: 't' })"))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        XCTAssertEqual(spec.type, "text")
        XCTAssertEqual(spec.props["content"], .string("hello"))
        XCTAssertEqual(spec.props["id"], .string("t"))
        XCTAssertTrue(spec.children.isEmpty)
    }

    func testHNestedChildren() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let script = "h('stack', { orientation: 'vertical' }, [h('text', { content: 'a' }), h('button', { title: 'Go' })])"
        let value = try XCTUnwrap(context.evaluateScript(script))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        let root = try CanvasElementParser.parseTree(spec)
        guard case .stack(let props, let children) = root else {
            return XCTFail("Expected stack root, got \(root)")
        }
        XCTAssertEqual(props.orientation, .vertical)
        XCTAssertEqual(children.count, 2)
        guard case .text(let textProps) = children[0] else {
            return XCTFail("Expected text child")
        }
        XCTAssertEqual(textProps.content, "a")
        guard case .button(let buttonProps) = children[1] else {
            return XCTFail("Expected button child")
        }
        XCTAssertEqual(buttonProps.title, "Go")
    }

    func testElementSpecPropsCoerceTypes() throws {
        let dict: [String: Any] = [
            "type": "box",
            "props": [
                "count": 3,
                "on": true
            ]
        ]
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: dict))
        XCTAssertEqual(spec.type, "box")
        XCTAssertEqual(spec.props["count"], .number(3))
        XCTAssertEqual(spec.props["on"], .bool(true))
    }

    func testNonObjectRootReturnsNil() {
        XCTAssertNil(CanvasScriptBox.elementSpec(from: ["type": 42]))
        XCTAssertNil(CanvasScriptBox.elementSpec(from: ["props": ["a": 1]]))
    }

    func testJsonValueHandlesNSNumberBoolean() {
        XCTAssertEqual(CanvasScriptBox.jsonValue(from: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(CanvasScriptBox.jsonValue(from: NSNumber(value: false)), .bool(false))
        XCTAssertEqual(CanvasScriptBox.jsonValue(from: NSNumber(value: 42)), .number(42))
    }

    func testHVariadicChildren() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let script = "h('stack', { orientation: 'horizontal' }, h('text', { content: 'one' }), h('text', { content: 'two' }))"
        let value = try XCTUnwrap(context.evaluateScript(script))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        XCTAssertEqual(spec.children.count, 2)
        XCTAssertEqual(spec.children[0].props["content"], .string("one"))
        XCTAssertEqual(spec.children[1].props["content"], .string("two"))
    }

    /// Mixed static and nested/mapped child arrays must flatten into one flat child list, in order.
    func testHFlattensNestedChildArrays() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let script = "h('stack', {}, h('text', { content: 'first' }), [h('text', { content: 'a' }), [h('text', { content: 'b' })]], h('text', { content: 'last' }))"
        let value = try XCTUnwrap(context.evaluateScript(script))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        XCTAssertEqual(spec.children.count, 4)
        XCTAssertEqual(spec.children.map { $0.props["content"] },
                       [.string("first"), .string("a"), .string("b"), .string("last")])
    }

    /// `null`/`undefined` children (e.g. from conditional mapping) must be omitted, not reject the tree.
    func testHOmitNullAndUndefinedChildren() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let script = "h('stack', {}, ['a','b','c'].map(function(i){ return i === 'b' ? null : h('text', { content: i }); }), [undefined])"
        let value = try XCTUnwrap(context.evaluateScript(script))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        XCTAssertEqual(spec.children.count, 2)
        XCTAssertEqual(spec.children.map { $0.props["content"] }, [.string("a"), .string("c")])
    }

    func testHBareStringChildOnText() throws {
        let context = try XCTUnwrap(JSContext())
        CanvasScriptBox.installH(in: context)
        let script = "h('text', null, 'hello world')"
        let value = try XCTUnwrap(context.evaluateScript(script))
        let object = try XCTUnwrap(value.toObject() as? [String: Any])
        let spec = try XCTUnwrap(CanvasScriptBox.elementSpec(from: object))
        XCTAssertEqual(spec.type, "text")
        XCTAssertEqual(spec.props["content"], .string("hello world"))
    }

    func testElementSpecDepthBounded() {
        var dict: [String: Any] = ["type": "stack"]
        var current = dict
        for _ in 0...CanvasLimits.maxDepth + 5 {
            let next: [String: Any] = ["type": "stack", "children": [current]]
            current = next
        }
        XCTAssertNil(CanvasScriptBox.elementSpec(from: current))
    }
}
