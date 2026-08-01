import Foundation

public enum TransformCategory: String, Sendable, CaseIterable {
    case caseConversion = "Case Conversion"
    case textCleaning = "Text Cleaning"
    case developerEncoding = "Developer & Encoding"
}

public enum TransformCase: String, CaseIterable, Sendable, Identifiable {
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case titleCase = "titleCase"
    case camelCase = "camelCase"
    case pascalCase = "pascalCase"
    case snakeCase = "snakeCase"
    case kebabCase = "kebabCase"
    case constantCase = "constantCase"
    
    case trimWhitespace = "trimWhitespace"
    case sortLines = "sortLines"
    case removeDuplicates = "removeDuplicates"
    case reverseText = "reverseText"
    
    case urlEncode = "urlEncode"
    case urlDecode = "urlDecode"
    case base64Encode = "base64Encode"
    case base64Decode = "base64Decode"
    case formatJSON = "formatJSON"
    
    public var id: String { rawValue }
    
    public var category: TransformCategory {
        switch self {
        case .uppercase, .lowercase, .titleCase, .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase:
            return .caseConversion
        case .trimWhitespace, .sortLines, .removeDuplicates, .reverseText:
            return .textCleaning
        case .urlEncode, .urlDecode, .base64Encode, .base64Decode, .formatJSON:
            return .developerEncoding
        }
    }
    
    public var displayName: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .camelCase: return "camelCase"
        case .pascalCase: return "PascalCase"
        case .snakeCase: return "snake_case"
        case .kebabCase: return "kebab-case"
        case .constantCase: return "CONSTANT_CASE"
        case .trimWhitespace: return "Trim Whitespace"
        case .sortLines: return "Sort Lines (A-Z)"
        case .removeDuplicates: return "Remove Duplicate Lines"
        case .reverseText: return "Reverse Text"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .formatJSON: return "Format JSON"
        }
    }
    
    public func transform(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return words.map { $0.capitalized }.joined(separator: " ")
        case .camelCase:
            guard let first = words.first?.lowercased() else { return text }
            let rest = words.dropFirst().map { $0.capitalized }
            return ([first] + rest).joined()
        case .pascalCase:
            return words.map { $0.capitalized }.joined()
        case .snakeCase:
            return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            return words.map { $0.lowercased() }.joined(separator: "-")
        case .constantCase:
            return words.map { $0.uppercased() }.joined(separator: "_")
        case .trimWhitespace:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sortLines:
            return text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case .removeDuplicates:
            var seen = Set<String>()
            return text.components(separatedBy: .newlines).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseText:
            return String(text.reversed())
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .urlDecode:
            return text.removingPercentEncoding ?? text
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return text }
            return decoded
        case .formatJSON:
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
                  let prettyString = String(data: prettyData, encoding: .utf8) else { return text }
            return prettyString
        }
    }
}

public struct TransformSubAction: Action {
    public let transformCase: TransformCase
    
    public var id: String { "builtin.transform.\(transformCase.rawValue)" }
    public var title: String { transformCase.displayName }
    public var icon: ActionIcon { .symbol("textformat") }
    
    public init(transformCase: TransformCase) {
        self.transformCase = transformCase
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let transformed = transformCase.transform(context.selection.text)
        return .paste(transformed)
    }
}

public struct TransformTextGroupAction: Action {
    public let id = "builtin.transform"
    public let title = "Transform Text"
    public let icon = ActionIcon.symbol("textformat")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .none
    }
}
