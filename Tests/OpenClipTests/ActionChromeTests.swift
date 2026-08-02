import XCTest
@testable import Core
@testable import OpenClip

final class ActionChromeTests: XCTestCase {
    func testBuiltinCopyActionChrome() {
        let copy = CopyAction()
        XCTAssertEqual(copy.chrome.badge, .none)
        XCTAssertEqual(copy.chrome.rowStyle, .standard)
        XCTAssertEqual(copy.chrome.popupBehavior, .perform)
        XCTAssertEqual(copy.chrome.source, .builtin)
    }

    func testCustomActionChrome() {
        let custom = CustomAction(id: "custom.test", title: "Test Custom", iconName: "star", type: .textSnippet(template: "Prompt"))
        XCTAssertEqual(custom.chrome.badge, .custom)
        XCTAssertEqual(custom.chrome.source, .custom)
    }

}
