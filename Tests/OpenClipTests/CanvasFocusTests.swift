import XCTest
import Core

final class CanvasFocusTests: XCTestCase {
    func testTextfieldWinsAnywhereInTree() {
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .button(CanvasButtonProps(id: "btn", title: "B", handler: .dispatch("go"))),
            .stack(CanvasStackProps(), [
                .textField(CanvasTextFieldProps(id: "field", value: ""))
            ])
        ])
        XCTAssertEqual(tree.firstInteractiveID(), "field")
    }

    func testFallsBackToButtonWhenNoTextfield() {
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .button(CanvasButtonProps(id: "btn", title: "B", handler: .dispatch("go"))),
            .toggle(CanvasToggleProps(id: "tog", value: false))
        ])
        XCTAssertEqual(tree.firstInteractiveID(), "btn")
    }

    func testDisabledButtonSkipped() {
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .button(CanvasButtonProps(id: "btn", title: "B", disabled: true, handler: .dispatch("go"))),
            .toggle(CanvasToggleProps(id: "tog", value: false))
        ])
        XCTAssertEqual(tree.firstInteractiveID(), "tog")
    }

    func testNilWhenNoFocusable() {
        let tree: CanvasComponent = .stack(CanvasStackProps(), [.text(CanvasTextProps(content: "static"))])
        XCTAssertNil(tree.firstInteractiveID())
    }

    func testListItemIDCounts() {
        let tree: CanvasComponent = .list(CanvasListProps(), [
            CanvasListSection(items: [CanvasListItem(title: "a")]),
            CanvasListSection(items: [CanvasListItem(id: "row2", title: "b")])
        ])
        XCTAssertEqual(tree.firstInteractiveID(), "row2")
    }

    func testLinkCountsAsInteractiveFallback() {
        let tree: CanvasComponent = .stack(CanvasStackProps(), [
            .text(CanvasTextProps(content: "static")),
            .link(CanvasLinkProps(id: "lnk", title: "Docs", url: URL(string: "https://x")!))
        ])
        XCTAssertEqual(tree.firstInteractiveID(), "lnk")
    }
}
