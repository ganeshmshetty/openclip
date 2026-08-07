// SearchAction.swift
// OpenClip
//
// Implements web search functionality by querying configurable search engine URL templates using selected text.
import Foundation

public struct SearchAction: ConfigurableAction {
    public let id = "builtin.search"
    public let title = "Search"
    public let icon = ActionIcon.symbol("magnifyingglass")
    public let configurationViewID = "builtin.search"
    public let preferenceIconName = "magnifyingglass"
    
    public var actionOptions: [ExtensionOption] {
        [
            ExtensionOption(
                identifier: "url",
                label: "Search Engine URL Template",
                type: .string,
                defaultValue: "https://www.google.com/search?q={query}"
            )
        ]
    }
    
    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
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
        let template = settingsStore.get(.searchURL)
        let targetTemplate = template.isEmpty ? "https://www.google.com/search?q={query}" : template
        
        if let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed) {
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
