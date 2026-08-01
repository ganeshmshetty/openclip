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
        
        let template = UserDefaults.standard.string(forKey: "action.search.url") ?? ""
        if !template.isEmpty, template.contains("{query}") {
            if let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: template.replacingOccurrences(of: "{query}", with: encodedQuery)) {
                return .openURL(url)
            }
        }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        
        if let url = components.url {
            return .openURL(url)
        }
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
    }
}
