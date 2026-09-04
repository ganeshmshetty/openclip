// GroupAction.swift
// OpenClip
//
// Pure Core action representing an extension `.group` row (Phase 8). A group materializes as a
// row whose chrome stamps `.showSubActions` plus one registry entry per sub-action; membership
// is the ID-prefix convention (no parentGroupID marker). perform is structural-only.
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when the
// group carries declarative rules; otherwise the default requires a non-blank selection.
import Foundation

public struct GroupAction: Action, SubActionProviding {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?
    public let keywords: [String]

    public init(
        id: String,
        title: String,
        icon: ActionIcon,
        chrome: ActionChrome,
        rules: ExtensionActionRules? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.chrome = chrome
        self.rules = rules
        self.keywords = keywords
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return rules.resolveVisibility(for: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return rules.resolveVisibility(for: context).match
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .none
    }

    // Sub-actions are the registry entries whose id is `\(self.id).\(subID)` (the uniform convention
    // used by DefaultActionFactory). The group itself, AI launchers, and the inline completion
    // pseudo-action are excluded.
    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        catalog.filter { action in
            guard action.id != self.id, action.id.hasPrefix(self.id + ".") else { return false }
            return !action.chrome.launchesAI && !ActionIdentity.isCompletionPseudoAction(action)
        }
    }
}