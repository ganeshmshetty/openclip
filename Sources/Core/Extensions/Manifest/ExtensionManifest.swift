// ExtensionManifest.swift
// OpenClip
//
// Defines codable structures for parsing extension package manifests and metadata definitions.
import Foundation

public struct ExtensionActionMetadata: Codable, Sendable, Equatable {
    public let id: String?
    public let title: String?
    public let icon: String?
    public let script: String?
    public let url: String?
    public let regex: String?
    public let type: String?
    public let scriptCode: String?

    public var kind: ExtensionActionKind {
        ExtensionActionKind(rawType: type ?? "url")
    }

    public init(
        id: String? = nil,
        title: String? = nil,
        icon: String? = nil,
        script: String? = nil,
        url: String? = nil,
        regex: String? = nil,
        type: String? = nil,
        scriptCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.script = script
        self.url = url
        self.regex = regex
        self.type = type
        self.scriptCode = scriptCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .identifier)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .legacyTitle)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
            ?? container.decodeIfPresent(String.self, forKey: .legacyIcon)
        self.script = try container.decodeIfPresent(String.self, forKey: .script)
            ?? container.decodeIfPresent(String.self, forKey: .legacyScript)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decodeIfPresent(String.self, forKey: .legacyURL)
        self.regex = try container.decodeIfPresent(String.self, forKey: .regex)
            ?? container.decodeIfPresent(String.self, forKey: .legacyRegex)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.scriptCode = try container.decodeIfPresent(String.self, forKey: .scriptCode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(script, forKey: .script)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(regex, forKey: .regex)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(scriptCode, forKey: .scriptCode)
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case identifier = "identifier"
        case title = "title"
        case legacyTitle = "Title"
        case icon = "icon"
        case legacyIcon = "Icon"
        case script = "script"
        case legacyScript = "Script"
        case url = "url"
        case legacyURL = "URL"
        case regex = "regex"
        case legacyRegex = "Regular Expression"
        case type = "type"
        case scriptCode = "scriptCode"
    }
}

public struct ExtensionManifest: Codable, Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let version: String?
    public let actions: [ExtensionActionMetadata]

    public init(
        identifier: String,
        name: String,
        version: String? = "1.0.0",
        actions: [ExtensionActionMetadata]
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.actions = actions
    }
}
