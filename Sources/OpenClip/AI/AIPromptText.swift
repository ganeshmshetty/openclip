// AIPromptText.swift
// OpenClip
//
// Pure text rules for free-form AI instructions typed by the user: how a query becomes the
// instruction sent to the provider, and how an instruction becomes a short title for a saved AI
// tool or a result card. Kept out of the views so they are unit-testable.
import Foundation

enum AIPromptText {
    /// Longest title a saved tool gets before it is elided with an ellipsis.
    static let maxToolTitleLength = 40

    /// The instruction handed to the provider: surrounding whitespace trimmed and interior runs of
    /// whitespace collapsed to one space, so an accidental double space never changes the prompt.
    static func instruction(from query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// A tool title for a prompt: the collapsed instruction with its first letter capitalised,
    /// cut back to `maxToolTitleLength` characters — at the last word boundary when there is one
    /// in the second half — and finished with an ellipsis when anything was dropped. Empty only
    /// for a blank prompt.
    static func toolTitle(for prompt: String) -> String {
        let collapsed = instruction(from: prompt)
        guard let first = collapsed.first else { return "" }
        let capitalised = String(first).uppercased() + collapsed.dropFirst()
        guard capitalised.count > maxToolTitleLength else { return capitalised }

        let budget = maxToolTitleLength - 1
        var cut = String(capitalised.prefix(budget))
        if let lastSpace = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: lastSpace) >= budget / 2 {
            cut = String(cut[..<lastSpace])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
