import Foundation

/// Declarative applicability rules shared by every extension runtime.
public struct ExtensionActionRules: Codable, Sendable, Equatable {
    public let requirements: ActionRequirements?
    public let legacyRegex: String?

    public init(requirements: ActionRequirements? = nil, legacyRegex: String? = nil) {
        self.requirements = requirements
        self.legacyRegex = legacyRegex
    }

    @MainActor
    public func resolveVisibility(for context: ActionContext) -> (enabled: Bool, match: ActionMatchInfo) {
        ActionVisibility.isEnabled(requirements: requirements, legacyRegex: legacyRegex, context: context)
    }
}
