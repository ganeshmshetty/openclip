// DefineAction.swift
// OpenClip
//
// Implements the dictionary lookup action for single selected words.
import Foundation

public struct DefineAction: ConfigurableAction {
    public let id = "builtin.define"
    public var title: String { String(localized: "Define") }
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

        // For non-space-delimited scripts (Chinese, Japanese, Korean), verify single-word boundary
        guard isSingleLinguisticWord(text) else { return false }
        
        // Exclude URLs, email addresses, and math symbols
        let isURL = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") || text.contains("www.")
        let hasMathSymbol = text.contains("+") || text.contains("*") || text.contains("/") || text.contains("=") || text.contains("%")
        
        guard !isURL && !hasMathSymbol else { return false }
        
        guard let definition = lookup(text), !definition.isEmpty else { return false }
        return true
    }

    private func isSingleLinguisticWord(_ text: String) -> Bool {
        let hasCJK = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x3040...0x309F).contains(scalar.value) ||
            (0x30A0...0x30FF).contains(scalar.value) ||
            (0xAC00...0xD7AF).contains(scalar.value)
        }
        guard hasCJK else { return true }

        let cfText = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfText))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            range,
            kCFStringTokenizerUnitWord,
            CFLocaleCopyCurrent()
        ) else {
            return true
        }

        var tokenCount = 0
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while tokenType != [] {
            if tokenType.contains(.normal) {
                tokenCount += 1
                if tokenCount > 1 { return false }
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return tokenCount <= 1
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let definition = lookup(text), !definition.isEmpty else { return .none }
        return .text(definition)
    }
}
