// ExtensionActionKind.swift
// OpenClip
//
// Defines normalized action kind types supported by extension manifests, such as URL templates, scripts, JavaScript handlers,
// text snippets, web search, and schema-only kinds (keyPress, service, shortcut, group) whose runtimes land in Phase 8.
import Foundation

public enum ExtensionActionKind: String, Codable, Sendable, Equatable {
    case url
    case js
    case applescript
    case shellInline
    case scriptFile
    case textSnippet
    case webSearch
    case keyPress
    case service
    case shortcut
    case group

    /// Every raw `type` string (normalized lowercase) the host recognizes, used by manifest
    /// validation to reject unknown/unsupported kinds instead of the lenient `.url` fallback.
    public static let recognizedTypeStrings: Set<String> = [
        "url", "urltemplate",
        "js", "javascript",
        "applescript",
        "shellinline", "shell",
        "scriptfile", "script",
        "textsnippet", "snippet", "text",
        "websearch", "web", "search",
        "keypress", "keys",
        "service", "servicemenu",
        "shortcut", "keyboardshortcut",
        "group", "subactions"
    ]

    /// Whether `rawType` names a recognized action kind (case-insensitive). Absent values are
    /// treated as recognized because they default to `.url`.
    public static func isRecognized(rawType: String?) -> Bool {
        guard let rawType, !rawType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return recognizedTypeStrings.contains(rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public init(rawType: String) {
        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "url", "urltemplate":
            self = .url
        case "js", "javascript":
            self = .js
        case "applescript":
            self = .applescript
        case "shellinline", "shell":
            self = .shellInline
        case "scriptfile", "script":
            self = .scriptFile
        case "textsnippet", "snippet", "text":
            self = .textSnippet
        case "websearch", "web", "search":
            self = .webSearch
        case "keypress", "keys":
            self = .keyPress
        case "service", "servicemenu":
            self = .service
        case "shortcut", "keyboardshortcut":
            self = .shortcut
        case "group", "subactions":
            self = .group
        default:
            self = .url
        }
    }
}
