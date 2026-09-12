// AIActionTests.swift
// OpenClipTests

import XCTest
@testable import OpenClip
@testable import Core

@MainActor
final class AIActionTests: XCTestCase {
    private func makeContext(text: String) -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection)
    }

    func testPerformReturnsSuccessWhenSelectionIsEmpty() async throws {
        let action = AIAction(presetID: "proofread", title: "Proofread")
        let context = makeContext(text: "")
        
        let result = try await action.perform(context)
        guard case .success = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
    }

    func testAIActionIconDefaultMatchesPresetIcon() {
        let action = AIAction(presetID: "proofread", title: "Proofread")
        XCTAssertEqual(action.icon, .text("Proofread"))
    }

    // MARK: - Preset ordering (drag to reorder in Preferences → AI → Actions)

    private var sample: [AIActionPreset] {
        ["proofread", "rewrite", "summarize", "explain"].map {
            AIActionPreset(id: $0, title: $0, prompt: "p", isEnabled: true)
        }
    }

    /// Dropping into the topmost gap (the insertion bar above the first row) puts the preset first.
    func testDroppingIntoTheTopGapMovesToFirst() {
        let reordered = AIServiceManager.reordering(sample, moving: "explain", toGap: 0)
        XCTAssertEqual(reordered.map(\.id), ["explain", "proofread", "rewrite", "summarize"])
    }

    /// Gap indices are pre-removal, so dropping into the gap *above* "explain" (index 3) leaves
    /// the moved row directly before it.
    func testDroppingIntoAMiddleGapLandsInThatGap() {
        let reordered = AIServiceManager.reordering(sample, moving: "proofread", toGap: 3)
        XCTAssertEqual(reordered.map(\.id), ["rewrite", "summarize", "proofread", "explain"])
    }

    /// The gap below the last row appends.
    func testDroppingIntoTheBottomGapMovesToLast() {
        let reordered = AIServiceManager.reordering(sample, moving: "proofread", toGap: 4)
        XCTAssertEqual(reordered.map(\.id), ["rewrite", "summarize", "explain", "proofread"])
    }

    /// Both gaps touching a row are no-ops for that row — a drag that goes nowhere changes nothing.
    func testDroppingIntoAnAdjacentGapIsANoOp() {
        XCTAssertEqual(AIServiceManager.reordering(sample, moving: "rewrite", toGap: 1).map(\.id), sample.map(\.id))
        XCTAssertEqual(AIServiceManager.reordering(sample, moving: "rewrite", toGap: 2).map(\.id), sample.map(\.id))
    }

    /// Nothing traps: an unknown id or an out-of-range gap is handled, not crashed on.
    func testUnknownIDAndOutOfRangeGapAreSafe() {
        XCTAssertEqual(AIServiceManager.reordering(sample, moving: "nope", toGap: 0).map(\.id), sample.map(\.id))
        XCTAssertEqual(AIServiceManager.reordering(sample, moving: "proofread", toGap: 99).map(\.id),
                       ["rewrite", "summarize", "explain", "proofread"])
        XCTAssertEqual(AIServiceManager.reordering(sample, moving: "explain", toGap: -3).map(\.id),
                       ["explain", "proofread", "rewrite", "summarize"])
        XCTAssertEqual(AIServiceManager.reordering([], moving: "proofread", toGap: 0).count, 0)
    }

    /// A preset keeps its content across a move — reordering must not rewrite prompts or state.
    func testReorderPreservesPresetContent() {
        var presets = sample
        presets[3].prompt = "explain it simply"
        presets[3].isEnabled = false
        let moved = AIServiceManager.reordering(presets, moving: "explain", toGap: 0)
        XCTAssertEqual(moved.first?.prompt, "explain it simply")
        XCTAssertEqual(moved.first?.isEnabled, false)
    }

    // MARK: - Insertion bar geometry (Preferences → AI → Actions)

    /// Eight 30pt rows stacked from y=0, as the preset list lays them out.
    private var rowFrames: [CGRect] {
        (0..<4).map { CGRect(x: 0, y: CGFloat($0) * 30, width: 400, height: 30) }
    }

    /// The gap follows the cursor by row midpoints — the rule AppKit's insertion bar uses.
    func testInsertionGapFollowsRowMidpoints() {
        XCTAssertEqual(RowReordering.insertionGap(atY: 0, rowFrames: rowFrames), 0, "above the first row")
        XCTAssertEqual(RowReordering.insertionGap(atY: 14, rowFrames: rowFrames), 0, "top half of row 0")
        XCTAssertEqual(RowReordering.insertionGap(atY: 16, rowFrames: rowFrames), 1, "bottom half of row 0")
        XCTAssertEqual(RowReordering.insertionGap(atY: 46, rowFrames: rowFrames), 2, "bottom half of row 1")
        XCTAssertEqual(RowReordering.insertionGap(atY: 400, rowFrames: rowFrames), 4, "below the last row")
        XCTAssertEqual(RowReordering.insertionGap(atY: 10, rowFrames: []), 0, "empty list has one gap")
    }

    /// The bar is drawn in the gap — on a row edge, never across a row.
    func testInsertionBarSitsOnTheRowEdges() {
        XCTAssertEqual(RowReordering.insertionY(forGap: 0, rowFrames: rowFrames), 0)
        XCTAssertEqual(RowReordering.insertionY(forGap: 2, rowFrames: rowFrames), 60)
        XCTAssertEqual(RowReordering.insertionY(forGap: 4, rowFrames: rowFrames), 120, "trailing gap sits on the last row's bottom edge")
        XCTAssertNil(RowReordering.insertionY(forGap: 0, rowFrames: []))
    }

    func testAIActionIconForPreset() {
        XCTAssertEqual(AIAction.iconForPreset(presetID: "proofread"), .text("Proofread"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "rewrite"), .text("Rewrite"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "summarize"), .text("Summarize"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "explain"), .text("Explain"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "translate"), .text("Translate"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "fix_code"), .text("Fix Code"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "make_shorter"), .text("Make Shorter"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "formal_tone"), .text("Formal Tone"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "custom_other"), .text("custom_other"))
    }
}
