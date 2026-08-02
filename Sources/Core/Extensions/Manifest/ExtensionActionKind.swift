import Foundation

public enum ExtensionActionKind: String, Codable, Sendable, Equatable {
    case url
    case js
    case applescript
    case shellInline
    case scriptFile

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
        default:
            self = .url
        }
    }
}
