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
    public let requirements: ActionRequirements?
    public let after: ActionAfterBehavior?
    /// When true the JS runtime runs asynchronously: the host awaits the action's promise, provides
    /// the `openclip.fetch(url, options)` polyfill, and enforces the execution watchdog. When false
    /// (or absent) the legacy synchronous evaluation is used.
    public let isAsync: Bool?
    public let options: [ExtensionOptionMetadata]?
    public let subActions: [ExtensionActionMetadata]?
    public let keyPress: String?
    public let serviceName: String?
    public let shortcutName: String?
    public let menuRelevance: String?
    /// When true the host closes the popup immediately on click and shows a spinner toast until
    /// the action's result lands (slow actions like an AppleScript that activates an app).
    public let loading: Bool?
    /// Optional text for the loading spinner toast (shown while `loading: true`). When absent the
    /// host falls back to its default ("Opening <title>…").
    public let loadingMessage: String?

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
        scriptCode: String? = nil,
        requirements: ActionRequirements? = nil,
        after: ActionAfterBehavior? = nil,
        isAsync: Bool? = nil,
        options: [ExtensionOptionMetadata]? = nil,
        subActions: [ExtensionActionMetadata]? = nil,
        keyPress: String? = nil,
        serviceName: String? = nil,
        shortcutName: String? = nil,
        menuRelevance: String? = nil,
        loading: Bool? = nil,
        loadingMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.script = script
        self.url = url
        self.regex = regex
        self.type = type
        self.scriptCode = scriptCode
        self.requirements = requirements
        self.after = after
        self.isAsync = isAsync
        self.options = options
        self.subActions = subActions
        self.keyPress = keyPress
        self.serviceName = serviceName
        self.shortcutName = shortcutName
        self.menuRelevance = menuRelevance
        self.loading = loading
        self.loadingMessage = loadingMessage
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
        self.requirements = try container.decodeIfPresent(ActionRequirements.self, forKey: .requirements)
        self.after = try container.decodeIfPresent(ActionAfterBehavior.self, forKey: .after)
        self.isAsync = try container.decodeIfPresent(Bool.self, forKey: .isAsync)
        self.options = try container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .options)
        self.subActions = try container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .subActions)
            ?? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .subActionsDash)
        self.keyPress = try container.decodeIfPresent(String.self, forKey: .keyPress)
        self.serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        self.shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName)
        self.menuRelevance = try container.decodeIfPresent(String.self, forKey: .menuRelevance)
        self.loading = try container.decodeIfPresent(Bool.self, forKey: .loading)
        self.loadingMessage = try container.decodeIfPresent(String.self, forKey: .loadingMessage)
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
        try container.encodeIfPresent(requirements, forKey: .requirements)
        try container.encodeIfPresent(after, forKey: .after)
        try container.encodeIfPresent(isAsync, forKey: .isAsync)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(subActions, forKey: .subActions)
        try container.encodeIfPresent(keyPress, forKey: .keyPress)
        try container.encodeIfPresent(serviceName, forKey: .serviceName)
        try container.encodeIfPresent(shortcutName, forKey: .shortcutName)
        try container.encodeIfPresent(menuRelevance, forKey: .menuRelevance)
        try container.encodeIfPresent(loading, forKey: .loading)
        try container.encodeIfPresent(loadingMessage, forKey: .loadingMessage)
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
        case requirements = "requirements"
        case after = "after"
        case isAsync = "async"
        case options = "options"
        case subActions = "subActions"
        case subActionsDash = "sub-actions"
        case keyPress = "keyPress"
        case serviceName = "serviceName"
        case shortcutName = "shortcutName"
        case menuRelevance = "menuRelevance"
        case loading = "loading"
        case loadingMessage = "loadingMessage"
    }
}

public struct ExtensionOptionMetadata: Sendable, Codable, Equatable {
    public let identifier: String
    public let label: String
    public let type: String
    public let defaultValue: String?
    public let values: [String]?
    
    public init(identifier: String, label: String, type: String, defaultValue: String? = nil, values: [String]? = nil) {
        self.identifier = identifier
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.values = values
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decode(String.self, forKey: .legacyLabel)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decode(String.self, forKey: .legacyType)
        self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            ?? container.decodeIfPresent(String.self, forKey: .legacyDefaultValue)
        self.values = try container.decodeIfPresent([String].self, forKey: .values)
            ?? container.decodeIfPresent([String].self, forKey: .valuesOptions)
            ?? container.decodeIfPresent([String].self, forKey: .valuesLegacyOptions)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(label, forKey: .label)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(values, forKey: .values)
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier = "identifier"
        case id = "id"
        case legacyIdentifier = "Identifier"
        case label = "label"
        case legacyLabel = "Label"
        case type = "type"
        case legacyType = "Type"
        case defaultValue = "default"
        case legacyDefaultValue = "Default"
        case values = "values"
        case valuesOptions = "options"
        case valuesLegacyOptions = "Options"
    }
}

public struct ExtensionMetadata: Sendable, Codable, Equatable {
    public let identifier: String
    public let name: String
    public let actions: [ExtensionActionMetadata]
    public let options: [ExtensionOptionMetadata]?
    /// Declared package version (e.g. `"1.0.0"`). Ignored by the loader except for validation
    /// bookkeeping (`ManifestValidationRecord.declaredVersion`).
    public let version: String?
    /// Declared runtime capabilities. The host's known-capability set is **empty** on day one, so
    /// any non-empty list rejects the manifest at load time (see `ManifestCapabilityGate`).
    public let capabilities: [String]?
    
    public init(
        identifier: String,
        name: String,
        actions: [ExtensionActionMetadata],
        options: [ExtensionOptionMetadata]? = nil,
        version: String? = nil,
        capabilities: [String]? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.actions = actions
        self.options = options
        self.version = version
        self.capabilities = capabilities
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decode(String.self, forKey: .legacyName)
        // Support both "actions" (array) and "action" (singular object)
        if let array = try? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .actions) ?? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .legacyActions) {
            self.actions = array
        } else if let single = try? container.decodeIfPresent(ExtensionActionMetadata.self, forKey: .action) {
            self.actions = [single]
        } else {
            self.actions = []
        }
        self.options = try container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .options)
            ?? container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .legacyOptions)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(capabilities, forKey: .capabilities)
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier = "identifier"
        case id = "id"
        case legacyIdentifier = "Identifier"
        case name = "name"
        case legacyName = "Name"
        case actions = "actions"
        case action = "action"     // singular fallback
        case legacyActions = "Actions"
        case options = "options"
        case legacyOptions = "Options"
        case version = "version"
        case capabilities = "capabilities"
    }
}

public typealias ExtensionManifest = ExtensionMetadata
