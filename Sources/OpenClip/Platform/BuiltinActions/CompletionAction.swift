// CompletionAction.swift
// OpenClip
//
// Implements word completion actions using platform text dictionaries and word completion providers.
import Foundation
import Core

public struct CompletionAction: ConfigurableAction, WordCompletionProviding {
    public let id = "builtin.completion"
    public var title: String { String(localized: "Word Completion") }
    public var icon: ActionIcon { .symbol("text.badge.plus") }
    public var chrome: ActionChrome {
        ActionChrome(popupBehavior: .provideCompletions)
    }

    private let spellChecker: (any TextSpellChecking)?

    public init(spellChecker: (any TextSpellChecking)? = nil) {
        self.spellChecker = spellChecker
    }

    @MainActor
    private func resolvedSpellChecker() -> any TextSpellChecking {
        spellChecker ?? SystemTextSpellChecker.shared
    }
    
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
    
    @MainActor
    public func fetchCompletions(for text: String) -> [String] {
        TextLanguageDetector.suggestions(for: text, assessments: resolvedSpellChecker().assessments(for: text))
    }
}
