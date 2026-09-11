// AskAIAction.swift
// OpenClip
//
// The "Ask…" entry of AI Tools: an AI-sourced action (so it lists with the presets in the AI
// Tools bar and the search palette) that, instead of running a fixed prompt, opens the result
// card in its ask state — the selection as the body and the instruction field focused — so the
// user types what AI should do and refines from there. `AIActionSync` registers it ahead of the
// presets and keeps it out of the preset reconciliation.
import Foundation
import Core

/// An AI-sourced action that asks the user for the instruction before running. The popup
/// resolves it by conformance (never by id) and opens the ask card instead of a preset prompt.
protocol InstructionPromptingAction: Action {}

public struct AskAIAction: Action, InstructionPromptingAction {
    public init() {}

    public var id: String { "ai.ask" }
    public var title: String { String(localized: "Ask…") }
    public var icon: ActionIcon { .symbol("text.bubble") }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
    }

    /// Needs AI on and something to ask about.
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        AIServiceManager.shared.isAIEnabled && !context.selection.text.isEmpty
    }

    /// Defensive fallback: every AI surface routes `.ai` selections through the popup's AI flow
    /// (`PopupWindowController.runAISelection`), never `perform`.
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }
}
