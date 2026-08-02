import XCTest
@testable import Core
@testable import OpenClip

final class CustomActionDraftTests: XCTestCase {
    func testDraftValidationAndConversion() {
        var draft = CustomActionDraft()
        XCTAssertFalse(draft.isValid)

        draft.title = "  "
        XCTAssertFalse(draft.isValid)

        draft.title = "My Action"
        draft.kind = .webSearch
        draft.template = "https://example.com/search?q={query}"
        XCTAssertTrue(draft.isValid)

        let action = draft.toCustomAction(id: "custom.myaction")
        XCTAssertEqual(action?.title, "My Action")
        XCTAssertEqual(action?.id, "custom.myaction")
    }
}
