// GroupAction.swift
// OpenClip
//
// Pure Core action representing an extension `.group` row (Phase 8). A group materializes as a
// row whose chrome stamps `.showTransformMenu` plus one registry entry per sub-action; membership
// is the ID-prefix convention (no parentGroupID marker). perform is structural-only.
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when the
// group carries declarative rules; otherwise the default requires a non-blank selection.
import Foundation

public struct GroupAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?

    public init(
        id: String,
        title: String,
        icon: ActionIcon,
        chrome: ActionChrome,
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.chrome = chrome
        self.rules = rules
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).match
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .none
    }
}