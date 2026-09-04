// ExtensionManifest.swift
// OpenClip
//
// Defines codable structures for parsing extension package manifests and metadata definitions.
import Foundation

public struct ExtensionActionMetadata: Codable, Sendable, Equatable {
    public let id: String?
    public let title: String?
    public let localizedTitle: LocalizedStringValue?
    public let icon: String?
    public let script: String?
    public let url: String?
    public let regex: String?
    public let type: String?
    public let scriptCode: String?
    public let requirements: ActionRequirements?
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
    public let localizedLoadingMessage: LocalizedStringValue?
    /// Declares how a secondary (right-click / option-click) activation behaves. Decoded
    /// unconditionally — Core just carries it; the install-time validator enforces kind-scoping
    /// (only non-scripting kinds may declare it, never `javascript`).
    public let secondary: ExtensionSecondaryDeclaration?
    /// Toast shown after the action completes successfully. Valid on all kinds.
    public let toast: ExtensionToastDeclaration?
    /// Toast shown after a secondary (right-click / option-click) activation completes. Valid on
    /// all kinds.
    public let secondaryToast: ExtensionToastDeclaration?
    /// Search keywords for the action palette.
    public let keywords: [String]?

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
        isAsync: Bool? = nil,
        options: [ExtensionOptionMetadata]? = nil,
        subActions: [ExtensionActionMetadata]? = nil,
        keyPress: String? = nil,
        serviceName: String? = nil,
        shortcutName: String? = nil,
        menuRelevance: String? = nil,
        loading: Bool? = nil,
        loadingMessage: String? = nil,
        secondary: ExtensionSecondaryDeclaration? = nil,
        toast: ExtensionToastDeclaration? = nil,
        secondaryToast: ExtensionToastDeclaration? = nil,
        keywords: [String]? = nil,
        localizedTitle: LocalizedStringValue? = nil,
        localizedLoadingMessage: LocalizedStringValue? = nil
    ) {
        self.id = id
        self.title = title ?? localizedTitle?.resolve()
        self.localizedTitle = localizedTitle ?? title.map { LocalizedStringValue(string: $0) }
        self.icon = icon
        self.script = script
        self.url = url
        self.regex = regex
        self.type = type
        self.scriptCode = scriptCode
        self.requirements = requirements
        self.isAsync = isAsync
        self.options = options
        self.subActions = subActions
        self.keyPress = keyPress
        self.serviceName = serviceName
        self.shortcutName = shortcutName
        self.menuRelevance = menuRelevance
        self.loading = loading
        self.loadingMessage = loadingMessage ?? localizedLoadingMessage?.resolve()
        self.localizedLoadingMessage = localizedLoadingMessage ?? loadingMessage.map { LocalizedStringValue(string: $0) }
        self.secondary = secondary
        self.toast = toast
        self.secondaryToast = secondaryToast
        self.keywords = keywords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .identifier)
        let baseTitle = (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .title))
            ?? (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .legacyTitle))
        let titleLocales = (try? container.decodeIfPresent([String: String].self, forKey: .titleLocales))
            ?? (try? container.decodeIfPresent([String: String].self, forKey: .titles))
        let resolvedLocTitle = LocalizedStringValue.merge(base: baseTitle, locales: titleLocales)
        self.localizedTitle = resolvedLocTitle
        self.title = resolvedLocTitle?.resolve()
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
        self.isAsync = try container.decodeIfPresent(Bool.self, forKey: .isAsync)
        self.options = try container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .options)
        self.subActions = try container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .subActions)
            ?? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .subActionsDash)
        self.keyPress = try container.decodeIfPresent(String.self, forKey: .keyPress)
        self.serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        self.shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName)
        self.menuRelevance = try container.decodeIfPresent(String.self, forKey: .menuRelevance)
        self.loading = try container.decodeIfPresent(Bool.self, forKey: .loading)
        let baseLoading = try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .loadingMessage)
        let loadingLocales = try? container.decodeIfPresent([String: String].self, forKey: .loadingMessageLocales)
        let resolvedLocLoading = LocalizedStringValue.merge(base: baseLoading, locales: loadingLocales)
        self.localizedLoadingMessage = resolvedLocLoading
        self.loadingMessage = resolvedLocLoading?.resolve()
        self.secondary = try container.decodeIfPresent(ExtensionSecondaryDeclaration.self, forKey: .secondary)
        self.toast = try container.decodeIfPresent(ExtensionToastDeclaration.self, forKey: .toast)
        self.secondaryToast = try container.decodeIfPresent(ExtensionToastDeclaration.self, forKey: .secondaryToast)
            ?? container.decodeIfPresent(ExtensionToastDeclaration.self, forKey: .secondaryToastDash)
        if let list = try? container.decodeIfPresent([String].self, forKey: .keywords) {
            self.keywords = list
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .keywords) {
            self.keywords = str.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
        } else {
            self.keywords = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        if let localizedTitle, localizedTitle.values.count > 1 {
            try container.encode(localizedTitle, forKey: .title)
        } else {
            try container.encodeIfPresent(title, forKey: .title)
        }
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(script, forKey: .script)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(regex, forKey: .regex)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(scriptCode, forKey: .scriptCode)
        try container.encodeIfPresent(requirements, forKey: .requirements)
        try container.encodeIfPresent(isAsync, forKey: .isAsync)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(subActions, forKey: .subActions)
        try container.encodeIfPresent(keyPress, forKey: .keyPress)
        try container.encodeIfPresent(serviceName, forKey: .serviceName)
        try container.encodeIfPresent(shortcutName, forKey: .shortcutName)
        try container.encodeIfPresent(menuRelevance, forKey: .menuRelevance)
        try container.encodeIfPresent(loading, forKey: .loading)
        if let localizedLoadingMessage, localizedLoadingMessage.values.count > 1 {
            try container.encode(localizedLoadingMessage, forKey: .loadingMessage)
        } else {
            try container.encodeIfPresent(loadingMessage, forKey: .loadingMessage)
        }
        try container.encodeIfPresent(secondary, forKey: .secondary)
        try container.encodeIfPresent(toast, forKey: .toast)
        try container.encodeIfPresent(secondaryToast, forKey: .secondaryToast)
        try container.encodeIfPresent(keywords, forKey: .keywords)
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
        case loadingMessageLocales = "loadingMessageLocales"
        case titleLocales = "titleLocales"
        case titles = "titles"
        case secondary = "secondary"
        case toast = "toast"
        case secondaryToast = "secondaryToast"
        case secondaryToastDash = "secondary-toast"
        case keywords = "keywords"
    }
}

public struct ExtensionSecondaryDeclaration: Codable, Sendable, Equatable {
    public let type: String      // "copy" | "paste" | "openURL" | "toast" | "success" | "none"
    public let value: String?    // for copy/paste/openURL
    public let message: String?  // for toast
}

public struct ExtensionToastDeclaration: Codable, Sendable, Equatable {
    public let message: String
    public let localizedMessage: LocalizedStringValue?
    public let style: String?    // "success" | "error" | "info" (default success)

    public init(message: String, style: String? = nil, localizedMessage: LocalizedStringValue? = nil) {
        self.message = message
        self.style = style
        self.localizedMessage = localizedMessage ?? LocalizedStringValue(string: message)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseMessage = try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .message)
        let messageLocales = (try? container.decodeIfPresent([String: String].self, forKey: .messageLocales))
            ?? (try? container.decodeIfPresent([String: String].self, forKey: .messages))
        guard let resolved = LocalizedStringValue.merge(base: baseMessage, locales: messageLocales) else {
            throw DecodingError.keyNotFound(
                CodingKeys.message,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required key: message")
            )
        }
        self.localizedMessage = resolved
        self.message = resolved.resolve()
        self.style = try container.decodeIfPresent(String.self, forKey: .style)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let localizedMessage, localizedMessage.values.count > 1 {
            try container.encode(localizedMessage, forKey: .message)
        } else {
            try container.encode(message, forKey: .message)
        }
        try container.encodeIfPresent(style, forKey: .style)
    }

    enum CodingKeys: String, CodingKey {
        case message
        case messageLocales = "messageLocales"
        case messages = "messages"
        case style
    }
}

public struct ExtensionOptionMetadata: Sendable, Codable, Equatable {
    public let identifier: String
    public let label: String
    public let localizedLabel: LocalizedStringValue?
    public let type: String
    public let defaultValue: String?
    public let values: [String]?
    
    public init(
        identifier: String,
        label: String,
        type: String,
        defaultValue: String? = nil,
        values: [String]? = nil,
        localizedLabel: LocalizedStringValue? = nil
    ) {
        self.identifier = identifier
        self.label = label
        self.localizedLabel = localizedLabel ?? LocalizedStringValue(string: label)
        self.type = type
        self.defaultValue = defaultValue
        self.values = values
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        let baseLabel = (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .label))
            ?? (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .legacyLabel))
        let labelLocales = (try? container.decodeIfPresent([String: String].self, forKey: .labelLocales))
            ?? (try? container.decodeIfPresent([String: String].self, forKey: .labels))
        guard let resolvedLabel = LocalizedStringValue.merge(base: baseLabel, locales: labelLocales)
            ?? (try? container.decode(String.self, forKey: .legacyLabel)).map({ LocalizedStringValue(string: $0) }) else {
            throw DecodingError.keyNotFound(
                CodingKeys.label,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required key: label")
            )
        }
        self.localizedLabel = resolvedLabel
        self.label = resolvedLabel.resolve()
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
        if let localizedLabel, localizedLabel.values.count > 1 {
            try container.encode(localizedLabel, forKey: .label)
        } else {
            try container.encode(label, forKey: .label)
        }
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
        case labelLocales = "labelLocales"
        case labels = "labels"
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
    public let localizedName: LocalizedStringValue?
    public let description: String?
    public let localizedDescription: LocalizedStringValue?
    public let actions: [ExtensionActionMetadata]
    public let options: [ExtensionOptionMetadata]?
    /// Declared package version (e.g. `"1.0.0"`). Ignored by the loader except for validation
    /// bookkeeping (`ManifestValidationRecord.declaredVersion`).
    public let version: String?
    /// Declared runtime capabilities. The host's known-capability set is **empty** on day one, so
    /// any non-empty list rejects the manifest at load time (see `ManifestCapabilityGate`).
    public let capabilities: [String]?
    /// Minimum OpenClip app version required to run this package (e.g. `"1.5.0"`). Min-only;
    /// an older app loads the package but marks it incompatible. Absent → compatible with all.
    public let minOpenClipVersion: String?
    /// Search keywords for the extension actions.
    public let keywords: [String]?
    
    public init(
        identifier: String,
        name: String,
        actions: [ExtensionActionMetadata],
        options: [ExtensionOptionMetadata]? = nil,
        version: String? = nil,
        capabilities: [String]? = nil,
        minOpenClipVersion: String? = nil,
        keywords: [String]? = nil,
        localizedName: LocalizedStringValue? = nil,
        description: String? = nil,
        localizedDescription: LocalizedStringValue? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.localizedName = localizedName ?? LocalizedStringValue(string: name)
        self.description = description
        self.localizedDescription = localizedDescription ?? description.map { LocalizedStringValue(string: $0) }
        self.actions = actions
        self.options = options
        self.version = version
        self.capabilities = capabilities
        self.minOpenClipVersion = minOpenClipVersion
        self.keywords = keywords
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        let baseName = (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .name))
            ?? (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .legacyName))
        let nameLocales = (try? container.decodeIfPresent([String: String].self, forKey: .nameLocales))
            ?? (try? container.decodeIfPresent([String: String].self, forKey: .names))
        guard let resolvedName = LocalizedStringValue.merge(base: baseName, locales: nameLocales)
            ?? (try? container.decode(String.self, forKey: .legacyName)).map({ LocalizedStringValue(string: $0) }) else {
            throw DecodingError.keyNotFound(
                CodingKeys.name,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required key: name")
            )
        }
        self.localizedName = resolvedName
        self.name = resolvedName.resolve()

        let baseDesc = (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .description))
            ?? (try? container.decodeIfPresent(LocalizedStringValue.self, forKey: .legacyDescription))
        let descLocales = (try? container.decodeIfPresent([String: String].self, forKey: .descriptionLocales))
            ?? (try? container.decodeIfPresent([String: String].self, forKey: .descriptions))
        let resolvedDesc = LocalizedStringValue.merge(base: baseDesc, locales: descLocales)
        self.localizedDescription = resolvedDesc
        self.description = resolvedDesc?.resolve()
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
        self.minOpenClipVersion = try container.decodeIfPresent(String.self, forKey: .minOpenClipVersion)
        if let list = try? container.decodeIfPresent([String].self, forKey: .keywords) {
            self.keywords = list
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .keywords) {
            self.keywords = str.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
        } else {
            self.keywords = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        if let localizedName, localizedName.values.count > 1 {
            try container.encode(localizedName, forKey: .name)
        } else {
            try container.encode(name, forKey: .name)
        }
        if let localizedDescription, localizedDescription.values.count > 1 {
            try container.encode(localizedDescription, forKey: .description)
        } else {
            try container.encodeIfPresent(description, forKey: .description)
        }
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(minOpenClipVersion, forKey: .minOpenClipVersion)
        try container.encodeIfPresent(keywords, forKey: .keywords)
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier = "identifier"
        case id = "id"
        case legacyIdentifier = "Identifier"
        case name = "name"
        case legacyName = "Name"
        case nameLocales = "nameLocales"
        case names = "names"
        case description = "description"
        case legacyDescription = "Description"
        case descriptionLocales = "descriptionLocales"
        case descriptions = "descriptions"
        case actions = "actions"
        case action = "action"     // singular fallback
        case legacyActions = "Actions"
        case options = "options"
        case legacyOptions = "Options"
        case version = "version"
        case capabilities = "capabilities"
        case minOpenClipVersion = "minOpenClipVersion"
        case keywords = "keywords"
    }
}

public typealias ExtensionManifest = ExtensionMetadata
