// AIConversation.swift
// OpenClip
//
// Result-card session history, sent to the provider as labelled, already-applied context. Capped
// to fit small on-device context windows.
import Foundation

public struct AIChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIConversation: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let instruction: String
        public let result: String

        public init(instruction: String, result: String) {
            self.instruction = instruction
            self.result = result
        }
    }

    public var original: String
    /// Oldest first. The first step's instruction is the action's own prompt.
    public var steps: [Step]

    public init(original: String, steps: [Step]) {
        self.original = original
        self.steps = steps
    }

    /// Only the most recent steps are sent; older ones are summarised as a count.
    static let maxSteps = 5
    static let maxTextLength = 1500
    static let maxInstructionLength = 300
    /// Size at which the oldest steps stop being sent as chat turns.
    static let maxChatCharacters = 24_000

    public func appending(instruction: String, result: String) -> AIConversation {
        var copy = self
        copy.steps.append(Step(instruction: instruction, result: result))
        return copy
    }

    /// Current instruction first, then history labelled as already applied so it is not redone.
    public func followUpTask(current instruction: String) -> String {
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

    // MARK: - Chat turns

    /// The action prompt as system text plus the session as alternating turns, ending on `instruction`. Nil before the
    /// first result exists, when there is no turn to continue. Each assistant turn is the earlier result in the output
    /// contract, so the model keeps answering in it.
    func followUpRequest(instruction: String, customGuidelines: String?) -> (system: String, messages: [AIChatMessage])? {
        guard let task = steps.first?.instruction else { return nil }
        let system = AIRequestSupport.followUpSystemPrompt(for: task, customGuidelines: customGuidelines)
        return (system, chatMessages(instruction: instruction))
    }

    /// Drops the oldest steps until the turns fit `maxChatCharacters`; the latest result and instruction always stay.
    func chatMessages(instruction: String) -> [AIChatMessage] {
        var firstKept = 0
        while true {
            let messages = Self.turns(original: original, steps: steps, from: firstKept, instruction: instruction)
            let size = messages.reduce(0) { $0 + $1.content.count }
            if size <= Self.maxChatCharacters || firstKept >= steps.count - 1 { return messages }
            firstKept += 1
        }
    }

    private static func turns(original: String, steps: [Step], from first: Int, instruction: String) -> [AIChatMessage] {
        var messages: [AIChatMessage] = []
        for index in first..<steps.count {
            let step = steps[index]
            if index == first {
                // The first kept turn carries the text its instruction applies to: the original, or the result before it.
                let source = index == 0 ? original : steps[index - 1].result
                let opening = index == 0 ? "" : "\n\n" + step.instruction
                messages.append(.init(role: .user, content: AIRequestSupport.userContent(for: source) + opening))
            } else {
                messages.append(.init(role: .user, content: step.instruction))
            }
            messages.append(.init(role: .assistant, content: "<result>\n\(step.result)\n</result>"))
        }
        messages.append(.init(role: .user, content: instruction))
        return messages
    }
}
