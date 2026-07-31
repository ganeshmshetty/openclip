import Foundation

public struct ActionContext: Sendable {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    public let isEditable: Bool
    public let regexMatches: [String]
    
    public init(
        selection: SelectionContext,
        modifiers: ModifierFlags = [],
        isEditable: Bool = false,
        regexMatches: [String] = []
    ) {
        self.selection = selection
        self.modifiers = modifiers
        self.isEditable = isEditable
        self.regexMatches = regexMatches
    }
}
