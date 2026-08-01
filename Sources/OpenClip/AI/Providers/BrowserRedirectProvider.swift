import Foundation
import AppKit

@MainActor
public final class BrowserRedirectProvider: AIProvider {
    public var type: AIProviderType { .browser }
    
    public let template: String
    
    public init(template: String) {
        self.template = template.isEmpty ? "https://chatgpt.com/?q={text}" : template
    }
    
    public func process(prompt: String, text: String) async throws -> String {
        let fullQuery = "\(prompt): \(text)"
        let encodedQuery = fullQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = template.replacingOccurrences(of: "{text}", with: encodedQuery)
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return "Opening browser..."
        }
        return text
    }
}
