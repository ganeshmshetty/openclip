import XCTest
@testable import Core

final class ActionSearchTests: XCTestCase {
    private struct MockSearchAction: Action {
        let id: String
        let title: String
        let icon = ActionIcon.symbol("star")
        let chrome = ActionChrome()
        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .success }
    }

    private func item(_ id: String, _ title: String, _ keywords: String = "") -> ActionSearchIndex {
        ActionSearchIndex(
            id: id,
            title: title,
            keywords: keywords,
            action: MockSearchAction(id: id, title: title)
        )
    }

    func testEmptyQueryReturnsAllInInputOrder() {
        let items = [item("a", "Alpha"), item("b", "Beta"), item("c", "Gamma")]
        let result = ActionSearch.search("   ", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func testPrefixMatchesRankAboveContainsMatches() {
        let items = [item("a", "Search Web"), item("b", "Web Search"), item("c", "Search Actions")]
        let result = ActionSearch.search("sear", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "c", "b"])
    }

    func testMatchIsCaseInsensitive() {
        let items = [item("a", "Copy"), item("b", "Cut")]
        let result = ActionSearch.search("COPY", in: items)
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testKeywordsMatchRanksBelowTitleMatches() {
        let items = [item("a", "Look Up", "wikipedia"), item("b", "Define", "wikipedia")]
        let result = ActionSearch.search("wikipedia", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    func testNonMatchingQueryReturnsEmpty() {
        let items = [item("a", "Copy"), item("b", "Paste")]
        XCTAssertTrue(ActionSearch.search("zzz", in: items).isEmpty)
    }
}
