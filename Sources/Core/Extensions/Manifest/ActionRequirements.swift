// ActionRequirements.swift
// OpenClip
//
// Defines declarative action requirements and after-run behavior for extension manifest actions.
// Schema-only in Phase 1: these types decode but are not yet enforced by any runtime.
import Foundation

public struct ActionRequirements: Codable, Sendable, Equatable {
    public var regex: String?
    public var regexNegated: Bool
    public var apps: [String]?
    public var appsMode: AppsMode
    public var requiresSelection: Bool
    public var requiredOptions: [String]?

    public enum AppsMode: String, Codable, Sendable {
        case allow
        case deny
    }

    public init(
        regex: String? = nil,
        regexNegated: Bool = false,
        apps: [String]? = nil,
        appsMode: AppsMode = .allow,
        requiresSelection: Bool = false,
        requiredOptions: [String]? = nil
    ) {
        self.regex = regex
        self.regexNegated = regexNegated
        self.apps = apps
        self.appsMode = appsMode
        self.requiresSelection = requiresSelection
        self.requiredOptions = requiredOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.regex = try container.decodeIfPresent(String.self, forKey: .regex)
        self.regexNegated = try container.decodeIfPresent(Bool.self, forKey: .regexNegated)
            ?? container.decodeIfPresent(Bool.self, forKey: .regexNegatedDash) ?? false
        self.apps = try container.decodeIfPresent([String].self, forKey: .apps)
        self.appsMode = try container.decodeIfPresent(AppsMode.self, forKey: .appsMode)
            ?? container.decodeIfPresent(AppsMode.self, forKey: .appsModeDash) ?? .allow
        self.requiresSelection = try container.decodeIfPresent(Bool.self, forKey: .requiresSelection)
            ?? container.decodeIfPresent(Bool.self, forKey: .requiresSelectionDash) ?? false
        self.requiredOptions = try container.decodeIfPresent([String].self, forKey: .requiredOptions)
            ?? container.decodeIfPresent([String].self, forKey: .requiredOptionsDash)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(regex, forKey: .regex)
        try container.encodeIfPresent(regexNegated, forKey: .regexNegated)
        try container.encodeIfPresent(apps, forKey: .apps)
        try container.encodeIfPresent(appsMode, forKey: .appsMode)
        try container.encodeIfPresent(requiresSelection, forKey: .requiresSelection)
        try container.encodeIfPresent(requiredOptions, forKey: .requiredOptions)
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
        case requiredOptions = "requiredOptions"
        case requiredOptionsDash = "required-options"
    }
}

public enum ActionAfterBehavior: String, Codable, Sendable {
    case copyResult = "copy-result"
    case pasteResult = "paste-result"
    case showResult = "show-result"
    case none = "none"
    case `default` = "default"
}
