import AppKit
import Foundation
import Core

public struct CompletionAction: WordCompletionProviding {
    public let id = "builtin.completion"
    public var title: String { "Word Completion" }
    public var icon: ActionIcon { .symbol("text.badge.plus") }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strictly single word, 2 to 30 characters
        guard !text.isEmpty && text.count >= 2 && text.count <= 30 else { return false }
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count == 1 else { return false }
        
        // Must contain letters
        guard text.rangeOfCharacter(from: .letters) != nil else { return false }
        
        // Exclude URLs and math symbols
        let isURL = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") || text.contains("www.")
        let hasMathSymbol = text.contains("+") || text.contains("*") || text.contains("/") || text.contains("=") || text.contains("%")
        guard !isURL && !hasMathSymbol else { return false }
        
        return !fetchCompletions(for: text).isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let completions = fetchCompletions(for: text)
        if let first = completions.first {
            return .paste(first)
        }
        return .none
    }
    
    /// Helper to fetch top 3-4 completion or spelling suggestions from NSSpellChecker
    @MainActor
    public func fetchCompletions(for text: String) -> [String] {
        let spellChecker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var results: [String] = []
        
        // 1. Partial word completions
        if let completions = spellChecker.completions(forPartialWordRange: range, in: text, language: nil, inSpellDocumentWithTag: 0) {
            results.append(contentsOf: completions)
        }
        
        // 2. Spelling guesses if no partial completions
        if results.isEmpty {
            if let guesses = spellChecker.guesses(forWordRange: range, in: text, language: nil, inSpellDocumentWithTag: 0) {
                results.append(contentsOf: guesses)
            }
        }
        
        // Filter out duplicates & exact same word (case insensitive)
        var unique: [String] = []
        for word in results {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.lowercased() != text.lowercased() && !unique.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                unique.append(trimmed)
            }
            if unique.count >= 4 { break }
        }
        return unique
    }
}
