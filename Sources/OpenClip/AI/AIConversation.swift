// AIConversation.swift
// OpenClip
//
// What the result card has done so far in one session: the original selection and each
// instruction with the result it produced. A follow-up hands this to the provider as *context* —
// clearly labelled as history, separated from the current task, and marked as already applied —
// so the model can keep tone, language and intent consistent ("keep the greeting you added",
// "same style as before") instead of seeing only the latest text. Capped so it stays within the
// smaller on-device context windows.
import Foundation

struct AIConversation: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let instruction: String
        let result: String
    }

    /// The text the session started from (the selection).
    var original: String
    /// Every instruction run in this session with its result, oldest first.
    var steps: [Step]

    /// How many of the most recent steps are sent; older ones are summarised as a count.
    static let maxSteps = 5
    /// Longest result (or original) sent verbatim; longer ones are cut with an ellipsis.
    static let maxTextLength = 1500
    /// Longest instruction sent verbatim (preset prompts can be long).
    static let maxInstructionLength = 300

    func appending(instruction: String, result: String) -> AIConversation {
        var copy = self
        copy.steps.append(Step(instruction: instruction, result: result))
        return copy
    }

    /// The task section for a follow-up: the current instruction first, then the history block.
    /// The history is explicitly context — already applied, not to be redone — and the last
    /// step's result is identified as the `<text>` block the model is asked to transform.
    func followUpTask(current instruction: String) -> String {
        var lines: [String] = []
        lines.append("CURRENT TASK (apply this to the text in the <text> block):")
        lines.append(instruction)
        lines.append("")
        lines.append("HISTORY — context only. These are the earlier steps of this session and they are ALREADY applied: do not redo them. Use them only to understand the user's intent and to keep the tone, language and formatting consistent with what they asked for before.")
        lines.append("Original selection:")
        lines.append(Self.quoted(original))
        let shown = steps.suffix(Self.maxSteps)
        let skipped = steps.count - shown.count
        if skipped > 0 {
            lines.append("(\(skipped) earlier step\(skipped == 1 ? "" : "s") omitted)")
        }
        for (offset, step) in shown.enumerated() {
            let number = skipped + offset + 1
            let isLast = offset == shown.count - 1
            lines.append("Step \(number) — the user asked: \"\(Self.clipped(step.instruction, to: Self.maxInstructionLength))\"")
            if isLast {
                lines.append("Result: the current text — it is the <text> block below.")
            } else {
                lines.append("Result:")
                lines.append(Self.quoted(step.result))
            }
        }
        if shown.isEmpty {
            lines.append("No earlier steps: the <text> block below is the original selection (or the text the card currently shows).")
        }
        lines.append("END OF HISTORY.")
        return lines.joined(separator: "\n")
    }

    private static func quoted(_ text: String) -> String {
        "\"\"\"\n\(clipped(text, to: maxTextLength))\n\"\"\""
    }

    static func clipped(_ text: String, to limit: Int) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
