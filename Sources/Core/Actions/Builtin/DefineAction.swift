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

    /// Declares a secondary-click toast: when `perform` returns `.copyDefinition` (secondary
    /// click), the popup surfaces "Copied definition" instead of a silent copy. The secondary
    /// outcome itself is code-branched in `perform` via `context.isSecondaryClick`.
    public var delivery: ActionDelivery? {
        ActionDelivery(secondaryToast: StatusFeedback(message: "Copied definition", style: .success))
    }

    public init() {}

    
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
        
        return !isURL && !hasMathSymbol
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A secondary click (right-click or ⇧-click) copies the dictionary definition headlessly
        // instead of opening Dictionary.app. The actual lookup is a platform effect resolved by the
        // effect door, so Core stays pure.
        if context.isSecondaryClick {
            return .copyDefinition(text)
        }
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed),
           let url = URL(string: "dict://\(encoded)") {
            return .openURL(url)
        }
        return .none
    }
}
