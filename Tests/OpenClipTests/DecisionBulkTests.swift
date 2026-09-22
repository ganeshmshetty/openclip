// DecisionBulkTests.swift
// OpenClipTests

import XCTest
@testable import Core

final class DecisionBulkTests: XCTestCase {
    func testSplitLinesCapsAtMaxUnits() {
        let text = (0..<150).map { "item \($0)" }.joined(separator: "\n")
        let units = DecisionBulkReducer.split(text, kind: .line, limits: DecisionBulkLimits(maxUnits: 100))
        XCTAssertEqual(units.count, 100)
        XCTAssertEqual(units.first?.text, "item 0")
    }

    func testSplitParagraphsAndWords() {
        let paragraphs = DecisionBulkReducer.split("one\n\ntwo\n\nthree", kind: .paragraph)
        XCTAssertEqual(paragraphs.map(\.text), ["one", "two", "three"])
        let words = DecisionBulkReducer.split("alpha beta gamma", kind: .word)
        XCTAssertEqual(words.map(\.text), ["alpha", "beta", "gamma"])
    }

    func testReduceKeepsAndMarks() {
        let units = [
            DecisionBulkUnit(id: 0, text: "keep me"),
            DecisionBulkUnit(id: 1, text: "drop me")
        ]
        let judgments = [
            DecisionBulkJudgment(unitID: 0, keep: true),
            DecisionBulkJudgment(unitID: 1, keep: false, mark: "spam")
        ]
        let reduced = DecisionBulkReducer.reduce(units: units, judgments: judgments)
        XCTAssertEqual(reduced.paste, "keep me")
        XCTAssertEqual(reduced.marks.count, 1)
        XCTAssertTrue(reduced.marks[0].contains("spam"))
    }

    func testBudgetGate() {
        XCTAssertTrue(DecisionBulkReducer.withinBudget(elapsed: 1, limits: .default))
        XCTAssertFalse(DecisionBulkReducer.withinBudget(elapsed: 99, limits: DecisionBulkLimits(budgetSeconds: 8)))
    }
}
