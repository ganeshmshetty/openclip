import Foundation

public struct SearchAction: ConfigurableAction {
    public let id = "builtin.search"
    public let title = "Search"
    public let icon = ActionIcon.symbol("magnifyingglass")
    public let configurationViewID = "builtin.search"
    public let preferenceIconName = "magnifyingglass"
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasURLPrefix = text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("www.")
        if hasURLPrefix {
            return false
        }
        return !text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let query = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = UserDefaults.standard.string(forKey: "action.search.url") ?? "https://www.google.com/search?q={query}"
        let targetTemplate = template.isEmpty ? "https://www.google.com/search?q={query}" : template
        
        if let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let urlString = targetTemplate.contains("{query}") ?
                targetTemplate.replacingOccurrences(of: "{query}", with: encodedQuery) :
                "https://www.google.com/search?q=\(encodedQuery)"
            
            if let url = URL(string: urlString) {
                return .openURL(url)
            }
        }
        
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
    }
}
