// PopupPageLayoutTests.swift
// OpenClipTests

import XCTest
import SwiftUI
@testable import OpenClip
@testable import Core

@MainActor
final class PopupPageLayoutTests: XCTestCase {
    private struct StubAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
        @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
        @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    func testBarWidthMetricsLevels() {
        XCTAssertEqual(PopupMetrics.barWidth(for: 1), 340.0)
        XCTAssertEqual(PopupMetrics.barWidth(for: 2), 440.0)
        XCTAssertEqual(PopupMetrics.barWidth(for: 3), 540.0)
        XCTAssertEqual(PopupMetrics.barWidth(for: 4), 650.0)
        XCTAssertEqual(PopupMetrics.barWidth(for: 5), 780.0)
        XCTAssertEqual(PopupMetrics.barWidth(for: 99), 540.0, "Unknown level must fallback to 540pt default")
    }

    func testEstimatedItemWidth() {
        let symbol = StubAction(id: "1", title: "Copy", icon: .symbol("doc.on.doc"))
        let shortText = StubAction(id: "2", title: "OK", icon: .text("OK"))
        let longText = StubAction(id: "3", title: "Formal Tone", icon: .text("Formal Tone"))

        XCTAssertEqual(PopupPageLayout.estimatedItemWidth(for: symbol), 34.0)
        XCTAssertEqual(PopupPageLayout.estimatedItemWidth(for: shortText), 34.0)
        let longWidth = PopupPageLayout.estimatedItemWidth(for: longText)
        XCTAssertGreaterThan(longWidth, 34.0)
        XCTAssertLessThanOrEqual(longWidth, 125.0)

        // Scale scaling
        let scaledSymbol = PopupPageLayout.estimatedItemWidth(for: symbol, scale: 1.2)
        XCTAssertEqual(scaledSymbol, 34.0 * 1.2, accuracy: 0.001)
    }

    func testComputePagesSinglePageFit() {
        let actions = (0..<4).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            leadingWidth: 0,
            trailingWidth: 34.0,
            maxBudget: 340.0
        )

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.count, 4)
    }

    func testComputePagesMultiPagePackingWithChevrons() {
        // 12 icon actions = 12 * 34 = 408pt > 340pt
        let actions = (0..<12).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            leadingWidth: 29.0, // completion chevron
            trailingWidth: 34.0, // search button
            maxBudget: 340.0
        )

        XCTAssertGreaterThan(pages.count, 1, "Must split across multiple pages when total width exceeds budget")
        let flat = pages.flatMap { $0.map(\.id) }
        XCTAssertEqual(flat, actions.map(\.id), "All actions must be preserved across pages without loss")
    }

    func testComputePagesWithWideTextActions() {
        let textActions = (0..<6).map {
            StubAction(id: "ai.\($0)", title: "Text Action \($0)", icon: .text("Very Long Action Label \($0)"))
        }

        let pages = PopupPageLayout.computePages(
            actions: textActions,
            leadingWidth: 0,
            trailingWidth: 0,
            maxBudget: 260.0 // Compact budget
        )

        XCTAssertGreaterThan(pages.count, 1)
        for page in pages {
            let width = PopupPageLayout.measuredBarWidth(
                actions: page,
                hasLeftChevron: true,
                hasRightChevron: true
            )
            XCTAssertLessThanOrEqual(width, 260.0 + 58.0)
        }
    }

    func testMeasuredBarWidth() {
        let a1 = StubAction(id: "1", title: "A", icon: .symbol("star"))
        let a2 = StubAction(id: "2", title: "B", icon: .symbol("star"))

        let withoutChevrons = PopupPageLayout.measuredBarWidth(
            actions: [a1, a2],
            hasLeftChevron: false,
            hasRightChevron: false,
            leadingWidth: 29.0,
            trailingWidth: 34.0
        )
        XCTAssertEqual(withoutChevrons, 29.0 + 34.0 + 68.0)

        let withChevrons = PopupPageLayout.measuredBarWidth(
            actions: [a1, a2],
            hasLeftChevron: true,
            hasRightChevron: true,
            leadingWidth: 29.0,
            trailingWidth: 34.0
        )
        XCTAssertEqual(withChevrons, 29.0 + 34.0 + 68.0 + 58.0)
    }
}
