import XCTest
@testable import Core

final class RichPasteboardPayloadTests: XCTestCase {
    func testShellResultMapperPasteContent() {
        let json = """
        {
            "type": "pasteContent",
            "value": "Hello world",
            "html": "<b>Hello world</b>",
            "rtf": "{\\\\rtf1 Hello world}"
        }
        """
        let result = ShellResultMapper.actionResult(from: json, actionID: "test.action")
        guard case .pasteContent(let payload) = result else {
            XCTFail("Expected .pasteContent result")
            return
        }
        XCTAssertEqual(payload.plainText, "Hello world")
        XCTAssertEqual(payload.html, "<b>Hello world</b>")
        XCTAssertEqual(payload.rtf, "{\\rtf1 Hello world}")
    }

    func testShellResultMapperCopyContent() {
        let json = """
        {
            "type": "copyContent",
            "value": "Plain copy",
            "html": "<i>Plain copy</i>",
            "rtf": "{\\\\rtf1 Plain copy}"
        }
        """
        let result = ShellResultMapper.actionResult(from: json, actionID: "test.action")
        guard case .copyContent(let payload) = result else {
            XCTFail("Expected .copyContent result")
            return
        }
        XCTAssertEqual(payload.plainText, "Plain copy")
        XCTAssertEqual(payload.html, "<i>Plain copy</i>")
        XCTAssertEqual(payload.rtf, "{\\rtf1 Plain copy}")
    }
}
