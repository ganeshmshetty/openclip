// InstantAIAction.swift
// OpenClip
//
// The parent of the Instant AI prompt surface. Never registered in the catalog and never a bar
// row: it exists so the popup's search mode can be scoped to it (`SearchScope(parent:children:)`)
// and `PopupView` renders `InstantPromptView` for a `composesPrompt` parent instead of the action
// palette — the same scoping mechanism group rows and the AI Tools launcher use.
import Foundation
import Core

public struct InstantAIAction: Action {
    public init() {}

    public var id: String { "ai.instant" }
    public var title: String { String(localized: "Instant AI") }
    public var icon: ActionIcon { .symbol("bolt.fill") }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, composesPrompt: true)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool { true }

    /// Never the entry point — the hotkey opens the prompt, the prompt runs AI.
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }
}
