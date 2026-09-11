import XCTest
@testable import OpenClip

/// The follow-up task text: the current instruction first, then the session history — labelled
/// as context, marked as already applied, original selection and earlier results quoted, the
/// last result identified as the `<text>` block — capped for small context windows.
final class AIConversationTests: XCTestCase {

    func testCurrentTaskComesFirstAndHistoryIsLabelledAsContext() {
        let conversation = AIConversation(
            original: "Our quarterly review is Thursday.",
            steps: [.init(instruction: "make it sound friendly", result: "Hi all! Our quarterly review is Thursday.")]
        )
        let task = conversation.followUpTask(current: "shorter")
        let currentAt = task.range(of: "CURRENT TASK")!.lowerBound
        let instructionAt = task.range(of: "shorter")!.lowerBound
        let historyAt = task.range(of: "HISTORY — context only")!.lowerBound
        XCTAssertLessThan(currentAt, instructionAt)
        XCTAssertLessThan(instructionAt, historyAt, "the new task is stated before any history")
        XCTAssertTrue(task.contains("ALREADY applied"))
        XCTAssertTrue(task.contains("do not redo them"))
        XCTAssertTrue(task.contains("Original selection:\n\"\"\"\nOur quarterly review is Thursday.\n\"\"\""))
        XCTAssertTrue(task.contains("Step 1 — the user asked: \"make it sound friendly\""))
        XCTAssertTrue(task.contains("Result: the current text — it is the <text> block below."), "the last result is the text being transformed, not repeated")
        XCTAssertFalse(task.contains("Hi all! Our quarterly review"), "the last result is not duplicated")
        XCTAssertTrue(task.hasSuffix("END OF HISTORY."))
    }

    func testEarlierResultsAreQuotedAndOnlyTheLastIsTheTextBlock() {
        let conversation = AIConversation(original: "orig", steps: [
            .init(instruction: "first", result: "result one"),
            .init(instruction: "second", result: "result two"),
        ])
        let task = conversation.followUpTask(current: "third")
        XCTAssertTrue(task.contains("Step 1 — the user asked: \"first\"\nResult:\n\"\"\"\nresult one\n\"\"\""))
        XCTAssertTrue(task.contains("Step 2 — the user asked: \"second\"\nResult: the current text"))
        XCTAssertFalse(task.contains("result two"))
    }

    func testNoStepsYetSaysSo() {
        let task = AIConversation(original: "orig", steps: []).followUpTask(current: "translate")
        XCTAssertTrue(task.contains("No earlier steps"))
        XCTAssertTrue(task.contains("Original selection:\n\"\"\"\norig\n\"\"\""))
    }

    func testHistoryIsCapped() {
        var conversation = AIConversation(original: String(repeating: "o", count: 5_000), steps: [])
        for i in 1...8 { conversation = conversation.appending(instruction: "step \(i)", result: String(repeating: "r", count: 3_000)) }
        conversation = conversation.appending(instruction: String(repeating: "i", count: 1_000), result: "last")
        let task = conversation.followUpTask(current: "now")
        XCTAssertTrue(task.contains("(4 earlier steps omitted)"), "only the most recent \(AIConversation.maxSteps) steps are sent")
        XCTAssertFalse(task.contains("step 4 "), "an omitted step's instruction is gone")
        XCTAssertTrue(task.contains("Step 5 — the user asked: \"step 5\""), "numbering stays absolute")
        XCTAssertTrue(task.contains(String(repeating: "o", count: AIConversation.maxTextLength) + "…"))
        XCTAssertFalse(task.contains(String(repeating: "o", count: AIConversation.maxTextLength + 1)))
        XCTAssertTrue(task.contains(String(repeating: "i", count: AIConversation.maxInstructionLength) + "…\""))
        XCTAssertLessThan(task.count, 12_000)
    }
}
