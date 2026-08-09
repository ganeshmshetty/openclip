import XCTest
import Core
@testable import OpenClip

/// Tests the drop-after-commit rule that `CanvasSessionView` applies on tree re-renders (the
/// Task 12 review finding: a dispatch that re-renders the tree AND moves focus in the same update
/// cycle could drop the blurred field's draft before its `.change` commit ran).
///
/// The logic is tested at the view-logic level via `CanvasSessionDraftPlan` rather than by hosting
/// a real `CanvasSessionView`: the bug lives in the *ordering* of two `.onChange` callbacks
/// (`.onChange(of: session.tree)` vs `.onChange(of: focusID)`), which SwiftUI drives from its own
/// update cycle and cannot be forced to a specific sequence from an XCTest host view. Extracting
/// the decision into `CanvasSessionDraftPlan` (a pure value type — the view just applies the plan)
/// makes every ordering deterministic to assert directly.
final class CanvasSessionViewTests: XCTestCase {

    /// A text-field tree with an `onChange` handler when `hasHandler` is true.
    private func fieldTree(id: String, hasHandler: Bool = true) -> CanvasComponent {
        .textField(CanvasTextFieldProps(id: id, value: "",
                                        onChange: hasHandler ? .effect(.notify(title: "t", body: "b")) : nil))
    }

    /// The fragments race: focus flips to B first, the tree publish is observed second, so at plan
    /// time `focused` is the NEW target and the field being left (A) must be flushed before drop.
    func testFocusMoveRaceCommitsLeftFieldBeforeDrop() {
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["A": "abc"], committed: [], focused: "B", tree: fieldTree(id: "A"))

        XCTAssertEqual(plan.commits, [.init(id: "A", value: "abc")], "left field A must ship as .change")
        XCTAssertEqual(plan.survivingDrafts, [:], "A was left, so nothing survives")
    }

    /// The blur already shipped A (focusID handler ran first) and remembered it in the committed
    /// set: the matching-blur tree pass must NOT ship A a second time.
    func testBlurCommitAlreadyShippedIsNotReshipped() {
        let tree = fieldTree(id: "A")
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["A": "abc"], committed: ["A"], focused: nil, tree: tree)

        XCTAssertEqual(plan.commits, [], "already-committed field must not be committed again")
        XCTAssertEqual(plan.survivingDrafts, [:])
    }

    /// A multi-field draft map with one already-committed field: only the uncommitted non-focused
    /// field flushes; the focused field's draft survives.
    func testMixedDraftMapFlushesOnlyUncommittedAndDropsOthers() {
        let tree = fieldTree(id: "A")
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["A": "abc", "C": "uncommitted"], committed: ["A"], focused: "C", tree: tree)

        XCTAssertEqual(plan.commits, [], "A is still in committed set, so nothing new ships")
        XCTAssertEqual(plan.survivingDrafts, ["C": "uncommitted"], "focused field keeps its draft")
    }

    /// The plan resolves the `.change` handler against the tree it is given (the OLD tree, which
    /// still owns the field being left). A field that a dispatch removed from the new tree still
    /// exists here, so its value still commits.
    func testHandlerResolvedAgainstGivenTreeKeepsRemovedFieldCommittees() {
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["A": "abc"], committed: [], focused: nil, tree: fieldTree(id: "A"))
        XCTAssertEqual(plan.commits, [.init(id: "A", value: "abc")])

        let gone = CanvasSessionDraftPlan.plan(
            drafts: ["A": "abc"], committed: [], focused: nil, tree: fieldTree(id: "OTHER"))
        XCTAssertEqual(gone.commits, [], "field absent from the tree ships nothing; drafts dropped")
        XCTAssertEqual(gone.survivingDrafts, [:])
    }

    /// A draft for a field whose `.onChange` is nil is dropped silently — never shipped.
    func testHandlerlessFieldDraftIsDroppedWithoutCommit() {
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["C": "nohandler"], committed: [], focused: nil,
            tree: fieldTree(id: "C", hasHandler: false))

        XCTAssertEqual(plan.commits, [])
        XCTAssertEqual(plan.survivingDrafts, [:])
    }

    /// The common in-progress case: focus stays on A, an unrelated dispatch re-renders the tree —
    /// the focused draft survives untouched (no commit, no drop).
    func testFocusedDraftSurvivesUnrelatedTreeRender() {
        let plan = CanvasSessionDraftPlan.plan(
            drafts: ["A": "typing..."], committed: [], focused: "A", tree: fieldTree(id: "A"))

        XCTAssertEqual(plan.commits, [])
        XCTAssertEqual(plan.survivingDrafts, ["A": "typing..."])
    }

    func testPlanEmptyWhenNoState() {
        let plan = CanvasSessionDraftPlan.plan(drafts: [:], committed: [], focused: nil, tree: fieldTree(id: "A"))
        XCTAssertTrue(plan.isEmpty)
    }
}