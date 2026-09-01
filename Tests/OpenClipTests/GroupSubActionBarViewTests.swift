// GroupSubActionBarViewTests.swift
import XCTest
@testable import OpenClip
@testable import Core

final class GroupSubActionBarViewTests: XCTestCase {
    @MainActor
    func testPaginationThreshold() {
        let totalPages = GroupSubActionBarView.totalPages(actionCount: 3, pageSize: 5)
        XCTAssertEqual(totalPages, 1)
    }

    @MainActor
    func testPaginationNeeded() {
        let totalPages = GroupSubActionBarView.totalPages(actionCount: 8, pageSize: 5)
        XCTAssertEqual(totalPages, 2)
    }

    @MainActor
    func testPagedSlice() {
        let ids = (0..<8).map { "stub.\($0)" }
        let page0 = GroupSubActionBarView.pagedSlice(of: ids, page: 0, pageSize: 5)
        XCTAssertEqual(page0, ["stub.0", "stub.1", "stub.2", "stub.3", "stub.4"])
        let page1 = GroupSubActionBarView.pagedSlice(of: ids, page: 1, pageSize: 5)
        XCTAssertEqual(page1, ["stub.5", "stub.6", "stub.7"])
    }

    @MainActor
    func testPagedSliceOutOfBounds() {
        let ids = (0..<3).map { "stub.\($0)" }
        let page1 = GroupSubActionBarView.pagedSlice(of: ids, page: 1, pageSize: 5)
        XCTAssertEqual(page1, [])
    }

    @MainActor
    func testPaginationZeroOrNegativePageSize() {
        let totalPages = GroupSubActionBarView.totalPages(actionCount: 5, pageSize: 0)
        XCTAssertEqual(totalPages, 5)
        let totalPagesNegative = GroupSubActionBarView.totalPages(actionCount: 5, pageSize: -1)
        XCTAssertEqual(totalPagesNegative, 5)
    }

    @MainActor
    func testEstimatedButtonWidthForSymbolAndText() {
        let symbolAction = TestAction(id: "sym", title: "Star", icon: .symbol("star"))
        let shortTextAction = TestAction(id: "t1", title: "AB", icon: .text("AB"))
        let longTextAction = TestAction(id: "t2", title: "Format JSON", icon: .text("Format JSON"))

        // Standard symbol icon defaults to 40
        XCTAssertEqual(GroupSubActionBarView.estimatedButtonWidth(for: symbolAction), 40)
        // Short text (<=2 chars) defaults to 40
        XCTAssertEqual(GroupSubActionBarView.estimatedButtonWidth(for: shortTextAction), 40)
        // Long text is estimated from character count + padding, capped at 125
        let longWidth = GroupSubActionBarView.estimatedButtonWidth(for: longTextAction)
        XCTAssertGreaterThan(longWidth, 40)
        XCTAssertLessThanOrEqual(longWidth, 125)
    }

    @MainActor
    func testComputePagesWidthBudgeting() {
        // Create 6 long-text actions each ~110pt
        let actions = (0..<6).map {
            TestAction(id: "act.\($0)", title: "Action \($0)", icon: .text("Very Long Action Label \($0)"))
        }

        let pages = GroupSubActionBarView.computePages(actions: actions, maxBudget: 340.0)
        // Since each is ~120pt, a 340pt budget fits at most 2-3 per page plus chevrons
        XCTAssertGreaterThan(pages.count, 1)
        // Flattened items match original actions
        let flatIDs = pages.flatMap { $0.map(\.id) }
        XCTAssertEqual(flatIDs, actions.map(\.id))
    }

    @MainActor
    func testMeasuredPageWidth() {
        let a1 = TestAction(id: "1", title: "A", icon: .symbol("star"))
        let a2 = TestAction(id: "2", title: "B", icon: .symbol("heart"))
        let widthWithoutChevrons = GroupSubActionBarView.measuredPageWidth(actions: [a1, a2], hasLeftChevron: false, hasRightChevron: false)
        XCTAssertEqual(widthWithoutChevrons, 80 + 6 + 4)

        let widthWithChevrons = GroupSubActionBarView.measuredPageWidth(actions: [a1, a2], hasLeftChevron: true, hasRightChevron: true)
        XCTAssertEqual(widthWithChevrons, 80 + 29 + 29)
    }
}

private struct TestAction: Action, Sendable {
    let id: String
    let title: String
    let icon: ActionIcon
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
