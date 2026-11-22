// PopupBarHighlightInsetsTests.swift
import XCTest
@testable import OpenClip

final class PopupBarHighlightInsetsTests: XCTestCase {
    func testLeadingTextUsesEdgeInsetOnlyOnTheLeadingSide() {
        let insets = PopupBarHighlightInsets.resolve(isText: true, leadingEdge: true, trailingEdge: false)
        XCTAssertEqual(insets.leading, 3)
        XCTAssertEqual(insets.trailing, 0)
        XCTAssertEqual(insets.contentOffset, 1.5)
    }

    func testTrailingTextUsesEdgeInsetOnlyOnTheTrailingSide() {
        let insets = PopupBarHighlightInsets.resolve(isText: true, leadingEdge: false, trailingEdge: true)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.trailing, 3)
        XCTAssertEqual(insets.contentOffset, -1.5)
    }

    func testInteriorTextHasNoInsetOrOffset() {
        let insets = PopupBarHighlightInsets.resolve(isText: true, leadingEdge: false, trailingEdge: false)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.trailing, 0)
        XCTAssertEqual(insets.contentOffset, 0)
    }

    func testSingleTextButtonIsSymmetric() {
        let insets = PopupBarHighlightInsets.resolve(isText: true, leadingEdge: true, trailingEdge: true)
        XCTAssertEqual(insets.leading, 3)
        XCTAssertEqual(insets.trailing, 3)
        XCTAssertEqual(insets.contentOffset, 0)
    }

    func testLeadingIconKeepsTheInteriorInset() {
        let insets = PopupBarHighlightInsets.resolve(isText: false, leadingEdge: true, trailingEdge: false)
        XCTAssertEqual(insets.leading, 3)
        XCTAssertEqual(insets.trailing, 2)
        XCTAssertEqual(insets.contentOffset, 0.5)
    }

    func testSubBarOuterInsetIsPassedThrough() {
        let insets = PopupBarHighlightInsets.resolve(
            isText: true,
            leadingEdge: true,
            trailingEdge: false,
            outerInset: 2
        )
        XCTAssertEqual(insets.leading, 2)
        XCTAssertEqual(insets.trailing, 0)
        XCTAssertEqual(insets.contentOffset, 1)
    }
}
