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

    private struct InlineStubAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon = .symbol("wand.and.stars")
        var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, isInlineResult: true) }
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

        XCTAssertEqual(PopupPageLayout.estimatedItemWidth(for: symbol), PopupMetrics.actionButtonWidth)
        XCTAssertEqual(PopupPageLayout.estimatedItemWidth(for: shortText), PopupMetrics.actionButtonWidth)
        let longWidth = PopupPageLayout.estimatedItemWidth(for: longText)
        XCTAssertGreaterThan(longWidth, PopupMetrics.actionButtonWidth)
        XCTAssertLessThanOrEqual(longWidth, 144.0)

        // Scale scaling
        let scaledSymbol = PopupPageLayout.estimatedItemWidth(for: symbol, scale: 1.2)
        XCTAssertEqual(scaledSymbol, PopupMetrics.actionButtonWidth * 1.2, accuracy: 0.001)
    }

    func testComputePagesSinglePageFit() {
        let actions = (0..<4).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            leadingWidth: 0,
            trailingWidth: PopupMetrics.actionButtonWidth,
            maxBudget: 340.0
        )

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.count, 4)
    }

    func testComputePagesMultiPagePackingWithChevrons() {
        // 12 icon actions = 12 * actionButtonWidth > 340pt
        let actions = (0..<12).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            leadingWidth: PopupPageLayout.chevronWidth, // completion chevron
            trailingWidth: PopupMetrics.actionButtonWidth, // search button
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
            XCTAssertLessThanOrEqual(width, 260.0 + 2 * PopupPageLayout.chevronWidth)
        }
    }

    func testInlinePreviewRepacksPagesAtRenderedWidth() {
        let actions = (0..<6).map { InlineStubAction(id: "inline.\($0)", title: "Inline \($0)") }
        let results = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, "1,234,567.89 USD") })

        // Six icon buttons fit the budget; the rendered preview text does not.
        let iconPacked = PopupPageLayout.computePages(actions: actions, maxBudget: 260.0)
        let previewPacked = PopupPageLayout.computePages(actions: actions, inlineResults: results, maxBudget: 260.0)

        XCTAssertEqual(iconPacked.count, 1)
        XCTAssertGreaterThan(previewPacked.count, 1, "Preview text must re-pack the page at its rendered width")
        XCTAssertEqual(iconPacked.flatMap { $0.map(\.id) }, previewPacked.flatMap { $0.map(\.id) }, "No action may be lost across re-packing")

        let width = PopupPageLayout.estimatedItemWidth(for: actions[0], inlineResult: "1,234,567.89 USD")
        XCTAssertGreaterThan(width, PopupMetrics.actionButtonWidth)
        XCTAssertLessThanOrEqual(width, PopupMetrics.inlineResultMaxWidth + 2 * PopupMetrics.inlineResultHorizontalPadding + 0.001)
    }

    func testMeasuredBarWidth() {
        let a1 = StubAction(id: "1", title: "A", icon: .symbol("star"))
        let a2 = StubAction(id: "2", title: "B", icon: .symbol("star"))

        let withoutChevrons = PopupPageLayout.measuredBarWidth(
            actions: [a1, a2],
            hasLeftChevron: false,
            hasRightChevron: false,
            leadingWidth: PopupPageLayout.chevronWidth,
            trailingWidth: PopupMetrics.actionButtonWidth
        )
        XCTAssertEqual(withoutChevrons, PopupPageLayout.chevronWidth + PopupMetrics.actionButtonWidth + 2 * PopupMetrics.actionButtonWidth)

        let withChevrons = PopupPageLayout.measuredBarWidth(
            actions: [a1, a2],
            hasLeftChevron: true,
            hasRightChevron: true,
            leadingWidth: PopupPageLayout.chevronWidth,
            trailingWidth: PopupMetrics.actionButtonWidth
        )
        XCTAssertEqual(withChevrons, PopupPageLayout.chevronWidth + PopupMetrics.actionButtonWidth + 2 * PopupMetrics.actionButtonWidth + 2 * PopupPageLayout.chevronWidth)
    }

    func testMaxScreenFractionAndMaxBarWidth() {
        XCTAssertEqual(PopupMetrics.maxScreenFraction, 0.50)
        XCTAssertEqual(PopupMetrics.maxBarWidth(for: 1440.0), 720.0)
        XCTAssertEqual(PopupMetrics.maxBarWidth(for: 1920.0), 960.0)
    }

    func testComputePagesLimitsByMaxItemsPerPage() {
        // 10 icon actions. Even if maxBudget is enormous (e.g. 2000pt),
        // maxItemsPerPage: 4 must paginate into chunks of at most 4 items.
        let actions = (0..<10).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            maxBudget: 2000.0,
            maxItemsPerPage: 4
        )

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].count, 4)
        XCTAssertEqual(pages[1].count, 4)
        XCTAssertEqual(pages[2].count, 2)
        let flat = pages.flatMap { $0.map { $0.id } }
        XCTAssertEqual(flat, actions.map(\.id))
    }

    func testComputePagesPaginatesWhenBudgetExceededBeforeMaxItemsPerPage() {
        // 10 icon actions with maxItemsPerPage: 8.
        // But maxBudget is 150pt (fits ~3 icon actions plus chevrons).
        let actions = (0..<10).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            maxBudget: 150.0,
            maxItemsPerPage: 8
        )

        // Must split into more than 2 pages because budget < 8 * actionButtonWidth
        XCTAssertGreaterThan(pages.count, 2)
        for page in pages {
            XCTAssertLessThanOrEqual(page.count, 8)
        }
        let flat = pages.flatMap { $0.map { $0.id } }
        XCTAssertEqual(flat, actions.map(\.id))
    }

    func testUnlimitedItemsPerPageExceedsTwelveAndStillPaginatesAtDifferentScales() {
        let actions = (0..<26).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }
        let widePages = PopupPageLayout.computePages(
            actions: actions, maxBudget: 864, maxItemsPerPage: Int.max)
        XCTAssertGreaterThan(widePages[0].count, 12)
        for scale in [CGFloat(0.85), 1.0, 1.22] {
            let pages = PopupPageLayout.computePages(
                actions: actions, maxBudget: 300, maxItemsPerPage: Int.max, scale: scale)
            XCTAssertGreaterThan(pages.count, 1)
            XCTAssertEqual(pages.flatMap { $0.map(\.id) }, actions.map(\.id))
            for (index, page) in pages.enumerated() {
                let chevrons = (index > 0 ? 1 : 0) + (index < pages.count - 1 ? 1 : 0)
                let width = CGFloat(page.count) * PopupMetrics.actionButtonWidth * scale
                    + CGFloat(chevrons) * PopupPageLayout.chevronWidth * scale
                XCTAssertLessThanOrEqual(width, 300)
            }
        }
    }

    func testComputePagesClampsZeroOrNegativeMaxItemsPerPage() {
        let actions = (0..<4).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        // A restored 0 or negative pageSize must not fragment into 1-action pages when all 4 fit
        let pagesZero = PopupPageLayout.computePages(actions: actions, maxBudget: 2000.0, maxItemsPerPage: 0)
        XCTAssertEqual(pagesZero.count, 1)
        XCTAssertEqual(pagesZero[0].count, 4)

        let pagesNeg = PopupPageLayout.computePages(actions: actions, maxBudget: 2000.0, maxItemsPerPage: -5)
        XCTAssertEqual(pagesNeg.count, 1)
        XCTAssertEqual(pagesNeg[0].count, 4)
    }
}
