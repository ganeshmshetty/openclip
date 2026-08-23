import XCTest
import Core
@testable import OpenClip

@MainActor
final class PopupModeStoreTests: XCTestCase {

    func testStoreDefaults() {
        let store = PopupModeStore()
        XCTAssertEqual(store.mode, .actions)
        XCTAssertNil(store.resultCard)
    }

    func testContentModePublishesResultCard() {
        let store = PopupModeStore()
        let payload = ResultCardPayload(text: "hi", isError: false, title: "AI Tools")
        store.resultCard = payload
        store.mode = .content
        XCTAssertEqual(store.mode, PopupMode.content)
        XCTAssertEqual(store.resultCard?.text, "hi")
        XCTAssertEqual(store.resultCard?.title, "AI Tools")
        XCTAssertNotEqual(PopupMode.actions, PopupMode.content)
        XCTAssertNotEqual(PopupMode.search, PopupMode.content)
    }

    func testResultCardPayloadFlagsError() {
        let payload = ResultCardPayload(text: "boom", isError: true)
        XCTAssertTrue(payload.isError)
        XCTAssertEqual(payload.title, "AI Tools")
    }
}
