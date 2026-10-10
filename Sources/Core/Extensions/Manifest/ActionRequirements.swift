// ActionRequirements.swift
// OpenClip
//
// Defines declarative input, destination, visibility, and option requirements for extensions.
import Foundation

public enum ActionInputRequirement: String, Codable, Sendable, CaseIterable {
    case optional
    case text
    case liveSelection
    case editableSelection
}

public struct ActionRequirements: Codable, Sendable, Equatable {
    public var regex: String?
    public var regexNegated: Bool
    public var apps: [String]?
    public var appsMode: AppsMode
    public var input: ActionInputRequirement
    public var requiresPasteTarget: Bool
    public var requiredOptions: [String]?
    public var content: [ContentType]?

    /// Compatibility view for source callers. New manifests should use `input`.
    @available(*, deprecated, message: "Use input instead")
    public var requiresSelection: Bool { input != .optional }

    public enum AppsMode: String, Codable, Sendable {
        case allow
        case deny
    }

    public init(
        regex: String? = nil,
        regexNegated: Bool = false,
        apps: [String]? = nil,
        appsMode: AppsMode = .allow,
        input: ActionInputRequirement? = nil,
        requiresSelection: Bool? = nil,
        requiresPasteTarget: Bool = false,
        requiredOptions: [String]? = nil,
        content: [ContentType]? = nil
    ) {
        self.regex = regex
        self.regexNegated = regexNegated
        self.apps = apps
        self.appsMode = appsMode
        self.input = input ?? (requiresSelection == false ? .optional : .text)
        self.requiresPasteTarget = requiresPasteTarget
        self.requiredOptions = requiredOptions
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.regex = try container.decodeIfPresent(String.self, forKey: .regex)
        self.regexNegated = try container.decodeIfPresent(Bool.self, forKey: .regexNegated)
            ?? container.decodeIfPresent(Bool.self, forKey: .regexNegatedDash) ?? false
        self.apps = try container.decodeIfPresent([String].self, forKey: .apps)
        self.appsMode = try container.decodeIfPresent(AppsMode.self, forKey: .appsMode)
            ?? container.decodeIfPresent(AppsMode.self, forKey: .appsModeDash) ?? .allow
        let input = try container.contains(.input) ? container.decode(ActionInputRequirement.self, forKey: .input) : nil
        let legacyCamel = try container.contains(.requiresSelection) ? container.decode(Bool.self, forKey: .requiresSelection) : nil
        let legacyDash = try container.contains(.requiresSelectionDash) ? container.decode(Bool.self, forKey: .requiresSelectionDash) : nil
        let pasteCamel = try container.contains(.requiresPasteTarget) ? container.decode(Bool.self, forKey: .requiresPasteTarget) : nil
        let pasteDash = try container.contains(.requiresPasteTargetDash) ? container.decode(Bool.self, forKey: .requiresPasteTargetDash) : nil
        if let legacyCamel, let legacyDash, legacyCamel != legacyDash {
            throw DecodingError.dataCorruptedError(forKey: .requiresSelectionDash, in: container,
                debugDescription: "Conflicting `requiresSelection` and `requires-selection` values; use only one legacy key or replace both with `input`.")
        }
        if input != nil, legacyCamel != nil || legacyDash != nil {
            throw DecodingError.dataCorruptedError(forKey: .input, in: container,
                debugDescription: "`input` cannot be combined with legacy `requiresSelection` or `requires-selection`; use only `input`.")
        }
        let legacy = legacyCamel ?? legacyDash
        self.input = input ?? (legacy == false ? .optional : .text)
        if let pasteCamel, let pasteDash, pasteCamel != pasteDash {
            throw DecodingError.dataCorruptedError(forKey: .requiresPasteTargetDash, in: container,
                debugDescription: "Conflicting `requiresPasteTarget` and `requires-paste-target` values; use only one key.")
        }
        self.requiresPasteTarget = pasteCamel ?? pasteDash ?? false
        self.requiredOptions = try container.decodeIfPresent([String].self, forKey: .requiredOptions)
            ?? container.decodeIfPresent([String].self, forKey: .requiredOptionsDash)
        if container.contains(.expression) {
            throw DecodingError.dataCorruptedError(forKey: .expression, in: container,
                debugDescription: "requirements.expression has been retired. Use requirements.content for native detection or requirements.regex for custom patterns.")
        }
        self.content = try container.contains(.content) ? container.decode([ContentType].self, forKey: .content) : nil
        if content?.isEmpty == true {
            throw DecodingError.dataCorruptedError(forKey: .content, in: container,
                debugDescription: "requirements.content must contain at least one of: url, email, date, path, phone, address.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(regex, forKey: .regex)
        try container.encodeIfPresent(regexNegated, forKey: .regexNegated)
        try container.encodeIfPresent(apps, forKey: .apps)
        try container.encodeIfPresent(appsMode, forKey: .appsMode)
        try container.encode(input, forKey: .input)
        if requiresPasteTarget { try container.encode(true, forKey: .requiresPasteTarget) }
        try container.encodeIfPresent(requiredOptions, forKey: .requiredOptions)
        try container.encodeIfPresent(content, forKey: .content)
    }

    enum CodingKeys: String, CodingKey {
        case regex
        case regexNegated = "regexNegated"
        case regexNegatedDash = "regex-negated"
        case apps
        case appsMode = "appsMode"
        case appsModeDash = "apps-mode"
        case requiresSelection = "requiresSelection"
        case requiresSelectionDash = "requires-selection"
        case input
        case requiresPasteTarget
        case requiresPasteTargetDash = "requires-paste-target"
        case requiredOptions = "requiredOptions"
        case requiredOptionsDash = "required-options"
        case expression // Decode-only: reject retired rules rather than silently dropping a gate.
        case content
    }
}
