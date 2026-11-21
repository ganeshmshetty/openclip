import XCTest
import CoreGraphics
@testable import Core

final class SelectionContextTests: XCTestCase {
    func testWithTextReplacesTextAndKeepsSourceIdentity() {
        let original = SelectionContext(
            text: "old text",
            sourceApp: AppIdentity(bundleIdentifier: "com.example.app", localizedName: "Example"),
            cursorPosition: CGPoint(x: 10, y: 20),
            mouseDownLocation: CGPoint(x: 4, y: 8),
            source: .ocr,
            isEditable: false,
            pasteTargetAvailable: false
        )

        let updated = original.with(text: "new text")

        XCTAssertEqual(updated.text, "new text")
        XCTAssertEqual(updated.source, .ocr)
        XCTAssertEqual(updated.sourceApp, original.sourceApp)
        XCTAssertEqual(updated.cursorPosition, original.cursorPosition)
        XCTAssertEqual(updated.mouseDownLocation, original.mouseDownLocation)
        XCTAssertEqual(updated.isEditable, false)
        XCTAssertEqual(updated.pasteTargetAvailable, false)
    }
}
