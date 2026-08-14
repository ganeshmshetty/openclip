import XCTest
import ApplicationServices
import CoreGraphics
@testable import OpenClip

final class AXTextControlStrategyTests: XCTestCase {

    private func target(
        selectedText: String? = nil,
        value: String? = nil,
        selectedTextRange: AnyObject? = nil,
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXTextField",
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: value,
            selectedTextRange: selectedTextRange,
            bounds: bounds
        )
    }

    private func cfRangeBox(location: Int, length: Int) -> AnyObject {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)!
    }

    func testReadUsesSelectedTextWhenPresent() {
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let result = AXTextControlStrategy.read(from: target(
            selectedText: "hello",
            value: "the full value",
            selectedTextRange: cfRangeBox(location: 0, length: 5),
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "hello")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testReadFallsBackToValueAndSelectedTextRangeSubstring() {
        let bounds = CGRect(x: 5, y: 6, width: 40, height: 4)
        let result = AXTextControlStrategy.read(from: target(
            selectedText: "",
            value: "The quick brown fox",
            selectedTextRange: cfRangeBox(location: 4, length: 5),
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "quick")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testReadTreatsRangeOffsetsAsUTF16CodeUnits() {
        // "e\u{0301}" is 2 UTF-16 code units but 1 Character; a range selecting just it is
        // location 0, length 2. Character-based offsets would over-read into the trailing "x".
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let result = AXTextControlStrategy.read(from: target(
            selectedText: "",
            value: "e\u{0301}x",
            selectedTextRange: cfRangeBox(location: 0, length: 2),
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "e\u{0301}")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testReadReturnsNilWhenSelectedTextIsEmpty() {
        let result = AXTextControlStrategy.read(from: target(
            selectedText: "",
            value: nil,
            selectedTextRange: nil
        ))

        XCTAssertNil(result)
    }

    func testReadReturnsNilWhenValueAndRangeUnavailable() {
        let result = AXTextControlStrategy.read(from: target(
            selectedText: nil,
            value: nil,
            selectedTextRange: nil
        ))

        XCTAssertNil(result)
    }

    func testReadReturnsNilWhenRangeIsOutOfBounds() {
        let result = AXTextControlStrategy.read(from: target(
            selectedText: nil,
            value: "short",
            selectedTextRange: cfRangeBox(location: 2, length: 99)
        ))

        XCTAssertNil(result)
    }

    func testReadReturnsNilWhenRangeHasZeroLength() {
        let result = AXTextControlStrategy.read(from: target(
            selectedText: nil,
            value: "short",
            selectedTextRange: cfRangeBox(location: 0, length: 0)
        ))

        XCTAssertNil(result)
    }
}