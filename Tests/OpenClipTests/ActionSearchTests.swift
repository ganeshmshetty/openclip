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

    private func item(_ id: String, _ title: String, _ keywords: String = "", _ usageRecency: Int = 0) -> ActionSearchIndex {
        ActionSearchIndex(
            id: id,
            title: title,
            keywords: keywords,
            action: MockSearchAction(id: id, title: title),
            usageRecency: usageRecency
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

    func testFuzzySubsequenceRanksBelowTitleContainsAndAboveKeyword() {
        // "sear": prefix on a, contains on b, fuzzy subsequence on c (s→e→a→r, not contiguous)
        let items = [
            item("a", "Search Web"),
            item("b", "Web Search"),
            item("c", "Satellite Earth Radar")
        ]
        let result = ActionSearch.search("sear", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func testFuzzySubsequenceBeatsKeywordContains() {
        // "exa": fuzzy subsequence on b (e-x…a in "Extra Audit"), keyword contains on a
        let items = [
            item("a", "Copy", "example"),
            item("b", "Extra Audit")
        ]
        let result = ActionSearch.search("exa", in: items)
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testFuzzyTightMatchRanksAboveLooseMatch() {
        // "sro": b starts at a word boundary ("S…" in "Sort Options"), a is interior and spread
        // out ("Assembler Resources" — s→r→o across two words). Both are fuzzy tier; the
        // tighter, better-anchored one wins even though it appears later in the input.
        let items = [
            item("a", "Assembler Resources"),
            item("b", "Sort Options")
        ]
        let result = ActionSearch.search("sro", in: items)
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testUsageRecencyBreaksTiesWithinTier() {
        // Both contain "look"; b was used more recently → b first, despite coming later in input.
        let items = [
            item("a", "Aaa Look", "", 1),
            item("b", "Bbb Look", "", 5)
        ]
        let result = ActionSearch.search("look", in: items)
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testBarOrderIsFinalTieBreakWhenRecencyTies() {
        // Same tier, same recency → input (bar) order wins.
        let items = [
            item("a", "Look Up", "", 3),
            item("b", "Look Out", "", 3)
        ]
        let result = ActionSearch.search("look", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }
}
