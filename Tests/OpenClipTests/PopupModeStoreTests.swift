import XCTest
import Core
@testable import OpenClip

@MainActor
final class PopupModeStoreTests: XCTestCase {

    func testStoreDefaults() {
        let store = PopupModeStore()
        XCTAssertEqual(store.mode, .actions)
        XCTAssertNil(store.content)
        XCTAssertNil(store.preview)
        XCTAssertNil(store.statusBanner)
    }

    func testContentModeIsEquatableAndPublishes() {
        let store = PopupModeStore()
        let session = CanvasSession(
            header: CanvasHeader(title: "AI Result", icon: "sparkles"),
            input: "hi",
            preferredSize: nil,
            scripting: nil,
            isAsync: false,
            tree: .text(CanvasTextProps(content: "hi", style: .body))
        )
        store.content = session
        store.mode = .content
        XCTAssertEqual(store.mode, PopupMode.content)
        XCTAssertEqual(store.content?.header.title, "AI Result")
        XCTAssertNotEqual(PopupMode.actions, PopupMode.content)
        XCTAssertNotEqual(PopupMode.search, PopupMode.content)
    }

    func testPreviewAndStatusPublish() {
        let store = PopupModeStore()
        store.preview = .text(CanvasTextProps(content: "2 + 2 = 4", style: .caption))
        XCTAssertNotNil(store.preview)
        store.statusBanner = StatusFeedback(message: "Copied", style: .success)
        XCTAssertEqual(store.statusBanner?.message, "Copied")
    }
}
