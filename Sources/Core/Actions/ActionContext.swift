import Foundation

public struct ActionContext: Sendable {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    
    public init(
        selection: SelectionContext,
        modifiers: ModifierFlags = []
    ) {
        self.selection = selection
        self.modifiers = modifiers
    }
}
