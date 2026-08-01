import Foundation

public struct URLTemplateAction: Action, Sendable {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let urlTemplate: String
    public let regexPattern: String?
    
    public init(id: String, title: String, icon: ActionIcon, urlTemplate: String, regexPattern: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.urlTemplate = urlTemplate
        self.regexPattern = regexPattern
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        
        if let pattern = regexPattern, !pattern.isEmpty {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } catch {
                return true
            }
        }
        
        return true
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = TextPlaceholderEngine.replacePlaceholders(in: urlTemplate, with: text, urlEncode: true)
        
        if let url = URL(string: urlString) {
            return .openURL(url)
        }
        
        return .none
    }
}
