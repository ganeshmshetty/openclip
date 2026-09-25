import Foundation
import UniformTypeIdentifiers

public enum FileOutputKind: String, Sendable, Equatable, CaseIterable {
    case image
    case pdf
    case text
    case other

    public static func resolve(mimeType: String?, fileExtension: String) -> FileOutputKind {
        if let mime = mimeType?.lowercased(), !mime.isEmpty {
            switch mime {
            case "application/pdf":
                return .pdf
            case "application/rtf", "text/rtf", "application/html", "text/html":
                return .other
            case "application/json", "application/xml", "text/xml",
                 "text/yaml", "application/yaml", "application/x-yaml",
                 "application/javascript", "application/x-javascript":
                return .text
            default:
                if mime.hasPrefix("image/") { return .image }
                if mime.hasPrefix("text/") { return .text }
                if let type = UTType(mimeType: mime) {
                    let kind = classify(type)
                    if kind != .other { return kind }
                }
            }
        }
        let ext = fileExtension.lowercased()
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return classify(type)
        }
        return .other
    }

    private static func classify(_ type: UTType) -> FileOutputKind {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .rtf) || type.conforms(to: .html) { return .other }
        if type.conforms(to: .text) { return .text }
        return .other
    }
}

extension FileOutputPayload {
    public var kind: FileOutputKind {
        FileOutputKind.resolve(mimeType: mimeType, fileExtension: fileExtension)
    }
}
