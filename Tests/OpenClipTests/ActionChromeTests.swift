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

    func testAIToolsActionChrome() {
        let launcher = AIToolsAction()
        XCTAssertEqual(launcher.chrome.source, .builtin)
        XCTAssertEqual(launcher.chrome.popupBehavior, .perform)
        XCTAssertTrue(launcher.chrome.launchesAI)
    }

    func testShowsLoadingDefaultsFalse() {
        let plain = CustomAction(id: "custom.plain", title: "Plain", iconName: "star", type: .textSnippet(template: "P"))
        XCTAssertFalse(plain.chrome.showsLoading)
    }

    func testShowsLoadingRoundTrips() {
        let chrome = ActionChrome(source: .builtin, showsLoading: true)
        XCTAssertTrue(chrome.showsLoading)
    }

    func testLoadingMessageDefaultsNilAndRoundTrips() {
        XCTAssertNil(ActionChrome(source: .builtin, showsLoading: true).loadingMessage)
        let chrome = ActionChrome(source: .builtin, showsLoading: true, loadingMessage: "Connecting to Music…")
        XCTAssertEqual(chrome.loadingMessage, "Connecting to Music…")
    }

}
