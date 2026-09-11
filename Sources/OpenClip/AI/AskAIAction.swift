// AskAIAction.swift
// OpenClip
//
// The "Ask AI" bar entry: a normal reorderable builtin action whose click swaps the bar for the
// prompt composer (`PromptComposerView`) — one field for a free-form instruction about the
// selection, with the user's recent instructions underneath. Modeled on `AIToolsAction`: the bar
// routes its click via `chrome.composesPrompt` (never `perform`), the palette excludes it, and
// its enable state follows `AIServiceManager.isAIEnabled`.
import Foundation
import Core

public struct AskAIAction: Action {
    public init() {}

    public var id: String { "builtin.askAI" }
    public var title: String { String(localized: "Ask AI") }
    public var icon: ActionIcon { .symbol("text.bubble") }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, composesPrompt: true)
    }

    /// Needs AI on and something to ask about: the composer has nothing to send otherwise.
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        AIServiceManager.shared.isAIEnabled && !context.selection.text.isEmpty
    }

    /// Defensive fallback: the bar routes via `chrome.composesPrompt`, so `perform` is never the
    /// entry point (same contract as `AIToolsAction`).
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }
}
