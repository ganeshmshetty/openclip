// PaletteAIPrompt.swift
// OpenClip
//
// The action-search palette's AI fallback. When a typed query matches no action, the query itself
// is offered as an instruction for the configured AI provider: run it once on the selection
// ("Ask AI"), or save it as a reusable AI tool — an `AIActionPreset`, which from then on is a
// searchable palette action and a row in Preferences → AI → Actions — and run it. Pure
// presentation model kept out of the view so the rules (when the rows appear, how a prompt is
// turned into a tool title) are unit-testable without hosting SwiftUI.
import Foundation

/// One row of the palette's AI fallback, in display order.
enum PaletteAIPromptRow: Hashable, CaseIterable {
    /// Run the typed text as a one-off AI instruction on the selection.
    case ask
    /// Save the typed text as a custom AI tool, then run it.
    case save
}

enum PaletteAIPrompt {
    /// Longest title a saved tool gets before it is elided with an ellipsis.
    static let maxToolTitleLength = 40

    /// What the palette found for the query, as far as the AI rows care.
    enum Results {
        /// Nothing matched: offer both rows.
        case none
        /// Only recent prompts matched: they already run the query, so offer just Save.
        case onlyRecentPrompts
        /// Real actions matched: no AI rows.
        case actions
    }

    /// The rows offered under the results for `query`: both when nothing matched, Save alone when
    /// only recent prompts matched, none when actions matched — and none for a blank query or
    /// with AI switched off (the plain "No matches" copy stays).
    static func rows(for query: String, aiEnabled: Bool, results: Results) -> [PaletteAIPromptRow] {
        guard aiEnabled, !instruction(from: query).isEmpty else { return [] }
        switch results {
        case .none: return PaletteAIPromptRow.allCases
        case .onlyRecentPrompts: return [.save]
        case .actions: return []
        }
    }

    /// The key hint under the AI rows: ⏎ replaces the selection (copies when the target can't
    /// paste), ⇧⏎ shows the result card first.
    static func hint(canPaste: Bool?) -> String {
        canPaste == false
            ? String(localized: "⏎ copy result · ⇧⏎ show result")
            : String(localized: "⏎ replace selection · ⇧⏎ show result")
    }

    /// The instruction handed to the provider: the query with surrounding whitespace trimmed and
    /// interior runs of whitespace collapsed to one space, so an accidental double space never
    /// changes the prompt.
    static func instruction(from query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// A tool title for a prompt: the collapsed instruction with its first letter capitalised,
    /// cut back to `maxToolTitleLength` characters — at the last word boundary when there is one
    /// in the second half, so "Rewrite this in a friendly, casual tone for…" rather than a word
    /// chopped mid-way — and finished with an ellipsis when anything was dropped. Also the result
    /// card's header for a one-off run. Empty only for a blank prompt.
    static func toolTitle(for prompt: String) -> String {
        let collapsed = instruction(from: prompt)
        guard let first = collapsed.first else { return "" }
        let capitalised = String(first).uppercased() + collapsed.dropFirst()
        guard capitalised.count > maxToolTitleLength else { return capitalised }

        let budget = maxToolTitleLength - 1 // room for the ellipsis
        var cut = String(capitalised.prefix(budget))
        if let lastSpace = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: lastSpace) >= budget / 2 {
            cut = String(cut[..<lastSpace])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The row's display title. The Ask row quotes the query verbatim so it reads as what will be
    /// sent; the Save row is a fixed label.
    static func rowTitle(_ row: PaletteAIPromptRow, query: String) -> String {
        switch row {
        case .ask:
            return String(localized: "Ask AI: “\(instruction(from: query))”")
        case .save:
            return String(localized: "Save as AI tool")
        }
    }

    /// The row's SF Symbol.
    static func rowSymbol(_ row: PaletteAIPromptRow) -> String {
        switch row {
        case .ask: return "sparkles"
        case .save: return "plus.circle"
        }
    }
}
