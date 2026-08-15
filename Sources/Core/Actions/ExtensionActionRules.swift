// ExtensionActionRules.swift
// OpenClip
//
// Holds the declarative visibility rules the factory attaches to every extension action it creates:
// requirements (regex, app allow/deny, requiresSelection, requiredOptions) and the legacy manifest
// `regex`. Consumed by ActionVisibility during enablement evaluation and by perform-time match
// plumbing.
//
// Codable + Equatable (additive over the plan's Sendable) so rules can ride on CustomAction, which
// synthesizes both conformances for the manifest shellInline path.
import Foundation

public struct ExtensionActionRules: Codable, Sendable, Equatable {
    public let requirements: ActionRequirements?
    public let legacyRegex: String?
    /// Derived data: the requirements.expression source compiled once by DefaultActionFactory.
    /// Skipped by Codable (decoded instances recompile via the factory); nil means no expression
    /// gate, matching pre-DSL behavior.
    public let compiledExpression: ValidateExpression?

    public init(
        requirements: ActionRequirements? = nil,
        legacyRegex: String? = nil,
        compiledExpression: ValidateExpression? = nil
    ) {
        self.requirements = requirements
        self.legacyRegex = legacyRegex
        self.compiledExpression = compiledExpression
    }

    /// The shared enablement entry point for extension actions. All extension action structs
    /// call this instead of reaching into ActionVisibility themselves.
    @MainActor
    public func resolveVisibility(for context: ActionContext) -> (enabled: Bool, match: ActionMatchInfo) {
        ActionVisibility.isEnabled(
            requirements: requirements,
            legacyRegex: legacyRegex,
            expression: compiledExpression,
            context: context
        )
    }

    private enum CodingKeys: String, CodingKey {
        case requirements, legacyRegex
    }

    // compiledExpression is derived data; the source string survives inside requirements.expression
    // and the factory recompiles it. Encode/decode the two declarative fields only.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requirements = try container.decodeIfPresent(ActionRequirements.self, forKey: .requirements)
        self.legacyRegex = try container.decodeIfPresent(String.self, forKey: .legacyRegex)
        self.compiledExpression = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requirements, forKey: .requirements)
        try container.encodeIfPresent(legacyRegex, forKey: .legacyRegex)
    }
}
