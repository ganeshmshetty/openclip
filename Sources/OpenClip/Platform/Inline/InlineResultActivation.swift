// InlineResultActivation.swift
// OpenClip
//
// Shared explicit-invocation seam for typed inline results. Views never call the action's
// unrestricted perform path for an inline item: a deliberate activation reuses the cached or
// in-flight value, or starts a fresh bounded restricted evaluation. Display-only items and
// color delivery restrictions are enforced here, not in each click handler.
import Foundation
import Core

@MainActor
enum InlineResultActivation {
    /// Returns the deliverable result for a deliberate activation, or nil when the item is
    /// informational, evaluation fails, or the value does not fit the declared output.
    static func invoke(
        action: any Action,
        context: ActionContext,
        sessionID: UUID? = nil
    ) async -> ActionResult? {
        guard action.chrome.isInlineResult, !action.chrome.displayOnly else { return nil }
        guard let value = await InlineResultEvaluator.shared.invoke(
            action: action,
            context: context,
            sessionID: sessionID
        ) else { return nil }
        return value.inlineActionResult
    }
}
