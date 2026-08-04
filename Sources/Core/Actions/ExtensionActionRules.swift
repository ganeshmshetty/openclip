// ExtensionActionRules.swift
// OpenClip
//
// Holds the declarative visibility/behavior rules the factory attaches to every extension action
// it creates: requirements (regex, app allow/deny, requiresSelection, requiredOptions), the legacy
// manifest `regex`, after-run behavior, and stay-visible. Consumed by ActionVisibility during
// enablement evaluation and by perform-time match plumbing.
//
// Codable + Equatable (additive over the plan's Sendable) so rules can ride on CustomAction, which
// synthesizes both conformances for the manifest shellInline path.
import Foundation

public struct ExtensionActionRules: Codable, Sendable, Equatable {
    public let requirements: ActionRequirements?
    public let legacyRegex: String?
    public let after: ActionAfterBehavior
    public let stayVisible: Bool

    public init(
        requirements: ActionRequirements? = nil,
        legacyRegex: String? = nil,
        after: ActionAfterBehavior = .default,
        stayVisible: Bool = false
    ) {
        self.requirements = requirements
        self.legacyRegex = legacyRegex
        self.after = after
        self.stayVisible = stayVisible
    }
}
