import XCTest
import Core
@testable import OpenClip

@MainActor
final class PopupModeStoreTests: XCTestCase {

    func testStoreDefaults() {
        let store = PopupModeStore()
        XCTAssertEqual(store.mode, .actions)
        XCTAssertNil(store.aiResult)
    }

    func testContentModePublishesAIResult() {
        let store = PopupModeStore()
        let payload = AIResultPayload(text: "hi", isError: false, title: "AI Tools")
        store.aiResult = payload
        store.mode = .content
        XCTAssertEqual(store.mode, PopupMode.content)
        XCTAssertEqual(store.aiResult?.text, "hi")
        XCTAssertEqual(store.aiResult?.title, "AI Tools")
        XCTAssertNotEqual(PopupMode.actions, PopupMode.content)
        XCTAssertNotEqual(PopupMode.search, PopupMode.content)
    }

    func testAIResultPayloadFlagsError() {
        let payload = AIResultPayload(text: "boom", isError: true)
        XCTAssertTrue(payload.isError)
        XCTAssertEqual(payload.title, "AI Tools")
    }
}
