// DecisionBulkAction.swift
// OpenClip
//
// "Bulk…" — the last entry in the Decision Tools group and a palette row of its own. It judges a
// whole selection item by item instead of as one piece of text, so it opens the bulk card
// (`ActionResult.decisionBulk`) rather than answering inline: the card is where the unit count,
// the word/row mode, the tool, progress and the per-category copy buttons live.
import Foundation
import Core

public struct DecisionBulkAction: Action {
    public init() {}

    public static let actionID = "builtin.decisionBulk"

    public var id: String { Self.actionID }
    public var title: String { String(localized: "Bulk…") }
    public var icon: ActionIcon { .symbol("list.bullet.rectangle") }

    /// Source `.decision` so it groups with the Decision tools everywhere (bar sub-group, palette,
    /// the Actions list); `DecisionActionSync` keeps it last in that group.
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .decision)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard DecisionServiceManager.shared.isDecisionsEnabled else { return false }
        // Nothing to split, or no tool that could judge the units.
        guard !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !DecisionBulkSession.eligibleTools().isEmpty
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .decisionBulk(context.selection.text)
    }
}
