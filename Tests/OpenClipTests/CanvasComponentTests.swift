import XCTest
import Core

final class CanvasComponentTests: XCTestCase {
    func testComponentIsSendableAndEquatable() {
        let a = CanvasComponent.text(CanvasTextProps(content: "hi"))
        let b = CanvasComponent.text(CanvasTextProps(content: "hi"))
        XCTAssertEqual(a, b)
        XCTAssertTrue(SendableCheck(a))
    }

    func testButtonEqualityIncludesHandler() {
        let one = CanvasComponent.button(CanvasButtonProps(title: "Go", handler: .effect(.paste("x"))))
        let two = CanvasComponent.button(CanvasButtonProps(title: "Go", handler: .effect(.copy("x"))))
        XCTAssertNotEqual(one, two)
    }

    func testTextFieldRequiresIDAndEquals() {
        let f1 = CanvasComponent.textField(CanvasTextFieldProps(id: "field", value: "a"))
        let f2 = CanvasComponent.textField(CanvasTextFieldProps(id: "field", value: "a"))
        XCTAssertEqual(f1, f2)
        XCTAssertNotEqual(f1, CanvasComponent.textField(CanvasTextFieldProps(id: "other", value: "a")))
    }

    func testCanvasEffectMapsToActionResultLeaves() {
        assertActionResultEqual(CanvasEffect.paste("s").asActionResult, .paste("s"))
        assertActionResultEqual(CanvasEffect.copy("s").asActionResult, .copy("s"))
        assertActionResultEqual(CanvasEffect.cut("s").asActionResult, .cut("s"))
        assertActionResultEqual(CanvasEffect.simulatePaste.asActionResult, .simulatePaste)
        assertActionResultEqual(CanvasEffect.openURL(URL(string: "https://x")!).asActionResult, .openURL(URL(string: "https://x")!))
    }
}

/// Compile-time Sendable conformance probe (no-op at runtime).
func SendableCheck<T: Sendable>(_ value: T) -> Bool { true }

/// `ActionResult` is `Sendable` but not `Equatable` (`.failure` carries `Error`), so leaf equality
/// is checked by pattern matching instead of `XCTAssertEqual`.
func assertActionResultEqual(_ actual: ActionResult, _ expected: ActionResult,
                             file: StaticString = #filePath, line: UInt = #line) {
    switch (actual, expected) {
    case (.paste(let a), .paste(let b)) where a == b: break
    case (.copy(let a), .copy(let b)) where a == b: break
    case (.cut(let a), .cut(let b)) where a == b: break
    case (.simulatePaste, .simulatePaste): break
    case (.showServices(let a), .showServices(let b)) where a == b: break
    case (.openURL(let a), .openURL(let b)) where a == b: break
    case (.keyPress(let a), .keyPress(let b)) where a == b: break
    case (.runShortcut(let an, let ai), .runShortcut(let bn, let bi)) where an == bn && ai == bi: break
    case (.notify(let at, let ab), .notify(let bt, let bb)) where at == bt && ab == bb: break
    default:
        XCTFail("\(actual) != \(expected)", file: file, line: line)
    }
}
