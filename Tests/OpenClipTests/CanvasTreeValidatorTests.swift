import XCTest
import Core

final class CanvasTreeValidatorTests: XCTestCase {
    private func stackOf(_ n: Int) -> CanvasComponent {
        var children: [CanvasComponent] = []
        for _ in 0..<n { children.append(.divider(CanvasDividerProps())) }
        return .stack(CanvasStackProps(), children)
    }

    func testValidTreePasses() throws {
        try CanvasTreeValidator.validate(.text(CanvasTextProps(content: "ok")))
        try CanvasTreeValidator.validate(.stack(CanvasStackProps(), [.text(CanvasTextProps(content: "a")), .divider(CanvasDividerProps())]))
    }

    func testTooManyNodesRejected() {
        let tree = stackOf(CanvasLimits.maxNodes + 1)
        XCTAssertThrowsError(try CanvasTreeValidator.validate(tree)) { error in
            XCTAssertEqual(error as? CanvasParseError, .tooManyNodes)
        }
    }

    func testDepthExceededRejected() {
        var nested: CanvasComponent = .divider(CanvasDividerProps())
        for _ in 0...CanvasLimits.maxDepth {
            nested = .stack(CanvasStackProps(), [nested])
        }
        XCTAssertThrowsError(try CanvasTreeValidator.validate(nested)) { error in
            XCTAssertEqual(error as? CanvasParseError, .depthExceeded)
        }
    }

    func testTooManyListItemsRejected() {
        var items: [CanvasListItem] = []
        for i in 0..<CanvasLimits.maxListItems + 1 {
            items.append(CanvasListItem(title: "\(i)"))
        }
        let tree = CanvasComponent.list(CanvasListProps(), [CanvasListSection(items: items)])
        XCTAssertThrowsError(try CanvasTreeValidator.validate(tree)) { error in
            XCTAssertEqual(error as? CanvasParseError, .tooManyListItems)
        }
    }

    func testTextTooLongRejected() {
        let long = String(repeating: "x", count: CanvasLimits.maxTextLength + 1)
        let tree = CanvasComponent.text(CanvasTextProps(content: long))
        XCTAssertThrowsError(try CanvasTreeValidator.validate(tree)) { error in
            XCTAssertEqual(error as? CanvasParseError, .textTooLong)
        }
    }

    func testDuplicateSiblingIDsRejected() {
        let dupTree = CanvasComponent.stack(CanvasStackProps(), [
            .text(CanvasTextProps(id: "dup", content: "first")),
            .text(CanvasTextProps(id: "dup", content: "second"))
        ])
        XCTAssertThrowsError(try CanvasTreeValidator.validate(dupTree)) { error in
            XCTAssertEqual(error as? CanvasParseError, .duplicateSiblingID("dup"))
        }
    }

    func testConstantsRenamed() {
        XCTAssertEqual(Constants.popupMaxHeight, 240)
    }
}
