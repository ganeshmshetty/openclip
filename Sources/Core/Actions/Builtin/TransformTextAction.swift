// TransformTextAction.swift
// OpenClip
//
// Implements text transformation actions such as letter case conversions, line sorting, whitespace trimming, and URL encoding.
// The default-on/off transform policy lives on TransformCase.defaultDisabledActionIDs.
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

    /// Transform sub-actions that are enabled by default. All other transform cases are
    /// registered but hidden until the user enables them in preferences.
    public static let defaultEnabledTransformCases: Set<TransformCase> = [
        .uppercase, .lowercase, .titleCase, .camelCase, .trimWhitespace, .formatJSON
    ]

    /// IDs of transform actions disabled by default: the transform group plus every
    /// sub-action not in `defaultEnabledTransformCases`. The registry reads this instead
    /// of duplicating the default-on/off policy.
    public static var defaultDisabledActionIDs: [String] {
        ["builtin.transform"] + allCases
            .filter { !defaultEnabledTransformCases.contains($0) }
            .map { "builtin.transform.\($0.rawValue)" }
    }
    
    public var category: TransformCategory {
        switch self {
        case .uppercase, .lowercase, .titleCase, .camelCase, .pascalCase:
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
    
    /// Whether this transform is useful for the given selection. Used to smart-filter the
    /// transform sub-action menu so an overloaded 14-item list becomes ~4-6 relevant items.
    ///
    /// Hybrid policy:
    /// - **Fast**: a cheap structural guard (multiline, non-whitespace words, URL/base64/JSON
    ///   markers, size cap) short-circuits before any real work runs.
    /// - **Reliable**: for the survivors, the authoritative `transform(_:)` is run and compared
    ///   against the input, so an entry that would be a no-op is never shown.
    /// - **Smart**: encode/decode cases only appear when the selection actually decodes
    ///   (e.g. `urlDecode` is hidden for `"hello world"`, `base64Decode` for plain prose).
    public func isRelevant(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWords = text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        let isMultiLine = text.components(separatedBy: .newlines).count > 1

        switch self {
        case .uppercase, .lowercase, .titleCase, .camelCase, .pascalCase:
            // No alphanumerics means no word-based conversion can change the text.
            guard hasWords else { return false }
            return transform(text) != text
        case .trimWhitespace:
            return text != trimmed
        case .sortLines, .removeDuplicates:
            // Sorting/deduplicating a single line is a no-op.
            guard isMultiLine else { return false }
            return transform(text) != text
        case .reverseText:
            // Single characters and palindromes are unchanged by reversal.
            guard text.count > 1 else { return false }
            return transform(text) != text
        case .urlEncode:
            // Encoding only changes the text when unsafe characters are present.
            return transform(text) != text
        case .urlDecode:
            // "%" or "%ZZ" contain the marker but removingPercentEncoding returns nil.
            guard text.contains("%"),
                  let decoded = text.removingPercentEncoding else { return false }
            return decoded != text
        case .base64Encode:
            return !text.isEmpty
        case .base64Decode:
            // Only relevant when the selection decodes to valid UTF-8 text, matching
            // transform(_:). Reject invalid padding ("====") and non-UTF-8 payloads,
            // which transform(_:) would leave untouched.
            guard !trimmed.isEmpty,
                  let data = Data(base64Encoded: trimmed),
                  let decoded = String(data: data, encoding: .utf8) else { return false }
            return decoded != text
        case .formatJSON:
            // Cheap shape guard: JSON objects/arrays start with { or [.
            guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
            // Very large selections skip the pretty-print diff (two full parses) and only
            // check that the text parses, so the menu never stalls on multi-MB JSON.
            guard text.count <= Constants.maxTransformCheckLength else {
                return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
            }
            // Reliable: hide when pretty-printing would not change the text. The options
            // must match transform(_:) exactly (prettyPrinted only) or the diff lies.
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
                  let pretty = String(data: prettyData, encoding: .utf8) else { return false }
            return pretty != text
        }
    }
    
    public func transform(_ text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return words(in: text).map { $0.capitalized }.joined(separator: " ")
        case .camelCase:
            let words = words(in: text)
            guard let first = words.first?.lowercased() else { return text }
            let rest = words.dropFirst().map { $0.capitalized }
            return ([first] + rest).joined()
        case .pascalCase:
            return words(in: text).map { $0.capitalized }.joined()
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
            return text.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed) ?? text
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
    
    private func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
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
    public let chrome = ActionChrome(badge: .none, rowStyle: .transformGroup, popupBehavior: .showTransformMenu, source: .builtin)
    
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
