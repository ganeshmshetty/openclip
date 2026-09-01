// AIAction.swift
// OpenClip
//
// Bridges an `AIActionPreset` into the Action registry so each AI preset surfaces as an
// individual action in the action-search palette and Preferences → Actions, while staying out
// of the popup bar (the reorderable `builtin.aiTools` action is the bar's entry point).
// `AIActionSync` keeps these
// in step with AIServiceManager's preset list: the title is snapshotted at registration time,
// while the runnable state and prompt are read live from AIServiceManager at invoke time.
import Foundation
import Core

/// Registry action for one AI preset. Never a popup bar row (`chrome.source == .ai` is excluded
/// in `ActionRegistry.availableActions`); the search palette routes `.ai` selections through the
/// popup's AI flow (`runAIPreset`) rather than `perform`, so results render in the native AI
/// result card just like clicking the preset in the AI Tools bar.
public struct AIAction: Action {
    public let presetID: String

    public var id: String { "ai.preset.\(presetID)" }
    public let title: String
    public var icon: ActionIcon { Self.iconForPreset(presetID: presetID, title: title) }

    public static func iconForPreset(presetID: String, title: String? = nil) -> ActionIcon {
        if let title, !title.isEmpty {
            return .text(title)
        }
        switch presetID {
        case "proofread": return .text("Proofread")
        case "rewrite": return .text("Rewrite")
        case "summarize": return .text("Summarize")
        case "explain": return .text("Explain")
        case "translate": return .text("Translate")
        case "fix_code": return .text("Fix Code")
        case "make_shorter": return .text("Make Shorter")
        case "formal_tone": return .text("Formal Tone")
        default: return .text(presetID)
        }
    }

    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
    }

    public init(presetID: String, title: String) {
        self.presetID = presetID
        self.title = title
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        preset()?.isEnabled ?? false
    }

    /// Defensive fallback for any non-palette caller (the palette routes `.ai` through the AI
    /// result-card flow). The popup's AI flow delivers the response via onAIResult, so this simply
    /// succeeds.
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }

    @MainActor
    private func preset() -> AIActionPreset? {
        AIServiceManager.shared.presets.first { $0.id == presetID }
    }
}
