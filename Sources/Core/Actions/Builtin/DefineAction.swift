import Foundation

public struct DefineAction: ConfigurableAction {
    public let id = "builtin.define"
    public var title: String { "Define" }
    public let configurationViewID = "builtin.define"
    public let preferenceIconName = "book"
    public var icon: ActionIcon {
        let useText = UserDefaults.standard.bool(forKey: "action.define.useText")
        return useText ? .text("Define") : .symbol("book")
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
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "dict://\(encoded)") {
            return .openURL(url)
        }
        return .none
    }
}
