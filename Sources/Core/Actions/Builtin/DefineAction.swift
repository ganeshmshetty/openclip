// DefineAction.swift
// OpenClip
//
// Implements the dictionary lookup action for single selected words.
import Foundation

public struct DefineAction: ConfigurableAction {
    public let id = "builtin.define"
    public var title: String { "Define" }
    public let preferenceIconName = "character.book.closed"
    public let icon = ActionIcon.symbol("character.book.closed")

    private let lookup: @Sendable (String) -> String?

    public init(lookup: @escaping @Sendable (String) -> String? = { _ in nil }) {
        self.lookup = lookup
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Length check: 1 to 40 characters
        guard !text.isEmpty && text.count <= 40 else { return false }
        
        // Word count check: strictly 1 word
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count == 1 else { return false }
        
        // Must contain letters
        guard text.rangeOfCharacter(from: .letters) != nil else { return false }
        
        // Exclude URLs, email addresses, and math symbols
        let isURL = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") || text.contains("www.")
        let hasMathSymbol = text.contains("+") || text.contains("*") || text.contains("/") || text.contains("=") || text.contains("%")
        
        guard !isURL && !hasMathSymbol else { return false }
        
        return lookup(text) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let definition = lookup(text), !definition.isEmpty else { return .none }
        return .text(definition)
    }
}
