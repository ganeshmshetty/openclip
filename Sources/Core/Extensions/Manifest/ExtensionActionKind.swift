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

    public init(rawType: String) {
        switch rawType.lowercased() {
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
