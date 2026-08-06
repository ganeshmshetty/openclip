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
        let content = PopupContent(title: "AI Result", rows: [.text("hi")], emphasis: .result)
        store.content = content
        store.mode = .content
        XCTAssertEqual(store.mode, PopupMode.content)
        XCTAssertEqual(store.content?.title, "AI Result")
        XCTAssertNotEqual(PopupMode.actions, PopupMode.content)
        XCTAssertNotEqual(PopupMode.search, PopupMode.content)
    }

    func testPreviewAndStatusPublish() {
        let store = PopupModeStore()
        store.preview = PopupContent(title: "Calc", subtitle: "2 + 2 = 4", emphasis: .info)
        XCTAssertEqual(store.preview?.emphasis, .info)
        store.statusBanner = StatusFeedback(message: "Copied", style: .success)
        XCTAssertEqual(store.statusBanner?.message, "Copied")
    }
}
