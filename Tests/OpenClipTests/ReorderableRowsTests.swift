// ReorderableRowsTests.swift
// OpenClipTests

import XCTest
@testable import OpenClip

/// The pure maths behind the drag-to-reorder list shared by the group editor and the AI prompt
/// library. The gap rules are covered next to their first caller in `AIActionTests`; this covers
/// the move itself, whose off-by-one (gap indices are read before the row is lifted out) is the
/// easy thing to get wrong.
final class ReorderableRowsTests: XCTestCase {
    private let ids = ["a", "b", "c", "d"]

    func testMovingIntoTheTopGapMakesItFirst() {
        XCTAssertEqual(RowReordering.reordering(ids, moving: "c", toGap: 0), ["c", "a", "b", "d"])
    }

    func testMovingIntoTheBottomGapMakesItLast() {
        XCTAssertEqual(RowReordering.reordering(ids, moving: "a", toGap: 4), ["b", "c", "d", "a"])
    }

    func testMovingDownLandsInTheGapTheDragHovered() {
        // Gap 3 is between "c" and "d" before "a" is lifted out, so "a" ends up after "c".
        XCTAssertEqual(RowReordering.reordering(ids, moving: "a", toGap: 3), ["b", "c", "a", "d"])
    }

    func testMovingUpLandsInTheGapTheDragHovered() {
        XCTAssertEqual(RowReordering.reordering(ids, moving: "d", toGap: 1), ["a", "d", "b", "c"])
    }

    func testDroppingBackIntoAnOwnAdjacentGapChangesNothing() {
        XCTAssertEqual(RowReordering.reordering(ids, moving: "b", toGap: 1), ids)
        XCTAssertEqual(RowReordering.reordering(ids, moving: "b", toGap: 2), ids)
    }

    func testUnknownIDAndOutOfRangeGapsAreSafe() {
        XCTAssertEqual(RowReordering.reordering(ids, moving: "zzz", toGap: 2), ids)
        XCTAssertEqual(RowReordering.reordering(ids, moving: "a", toGap: -5), ids)
        XCTAssertEqual(RowReordering.reordering(ids, moving: "a", toGap: 99), ["b", "c", "d", "a"])
    }

    func testASingleRowListSurvivesEveryGap() {
        XCTAssertEqual(RowReordering.reordering(["only"], moving: "only", toGap: 0), ["only"])
        XCTAssertEqual(RowReordering.reordering(["only"], moving: "only", toGap: 1), ["only"])
    }
}
