import Foundation

public struct TextPlaceholderEngine {
    public static func replacePlaceholders(in template: String, with text: String, urlEncode: Bool = true) -> String {
        let encodedText = urlEncode ? (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text) : text
        var result = template
        
        let placeholders = ["{text}", "{query}", "{popclip text}", "{openclip text}", "%@"]
        for placeholder in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: encodedText)
        }
        return result
    }
}
