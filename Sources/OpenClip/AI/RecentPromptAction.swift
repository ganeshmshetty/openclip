// RecentPromptAction.swift
// OpenClip
//
// A recent free-form AI instruction as a palette row. Never registered in the catalog: `PopupView`
// appends one per `AIPromptHistory` entry to the palette's search catalog, so a prompt the user
// ran before is found by typing any part of it ("slo" → "rewrite to slovak") and runs like the
// Ask AI row (⏎ replaces the selection, ⇧⏎ shows the result card). The palette resolves it by
// type, never by id, and routes it through `onRunAIPrompt` rather than `perform`.
import Foundation
import Core

public struct RecentPromptAction: Action {
    public let prompt: String

    public init(prompt: String) {
        self.prompt = prompt
    }

    public var id: String { "ai.recent." + prompt.lowercased() }
    public var title: String { prompt }
    public var icon: ActionIcon { .symbol("clock.arrow.circlepath") }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        AIServiceManager.shared.isAIEnabled && !context.selection.text.isEmpty
    }

    /// Defensive fallback: the palette routes recents through the AI prompt flow, never `perform`.
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }
}
