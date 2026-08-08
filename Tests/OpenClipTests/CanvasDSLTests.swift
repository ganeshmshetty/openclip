import XCTest
import Core

final class CanvasDSLTests: XCTestCase {
    func testBuildWrapsInVerticalStack() {
        let tree = Canvas.build {
            Canvas.text("2 + 2 = 4", style: .title)
            Canvas.button("Paste result", handler: .effect(.paste("4")))
            Canvas.button("Copy", handler: .effect(.copy("4")))
        }
        guard case .stack(let props, let children) = tree else {
            return XCTFail("expected stack, got \(tree)")
        }
        XCTAssertEqual(props.orientation, .vertical)
        XCTAssertEqual(children.count, 3)
    }

    func testConditionalBuilds() {
        let on = true
        let tree = Canvas.build {
            if on {
                Canvas.text("shown")
            } else {
                Canvas.divider
            }
        }
        guard case .stack(_, let children) = tree else {
            return XCTFail("expected stack")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0], .text(CanvasTextProps(content: "shown")))
    }

    func testEffectButtonHandler() {
        let tree = Canvas.build {
            Canvas.button("Paste", handler: .effect(.paste("x")))
        }
        guard case .stack(_, let children) = tree, case .button(let props) = children[0] else {
            return XCTFail("expected button")
        }
        XCTAssertEqual(props.handler, .effect(.paste("x")))
    }

    func testNativeBuildValidates() throws {
        let tree = Canvas.build {
            Canvas.text(String(repeating: "x", count: CanvasLimits.maxTextLength + 1))
        }
        XCTAssertThrowsError(try CanvasTreeValidator.validate(tree)) { error in
            XCTAssertEqual(error as? CanvasParseError, .textTooLong)
        }
    }
}
