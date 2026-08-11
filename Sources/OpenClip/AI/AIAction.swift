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
/// popup's AI flow (`runAIPreset`) rather than `perform`, so results render in the content canvas
/// just like clicking the preset in the AI Tools bar.
public struct AIAction: Action {
    public let presetID: String

    public var id: String { "ai.preset.\(presetID)" }
    public let title: String
    public var icon: ActionIcon { .symbol(Constants.defaultAIIconSymbol) }
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
    /// card flow). Runs the provider and shows the response in a popup content canvas.
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard let preset = preset(), !context.selection.text.isEmpty else { return .success }
        let provider = AIServiceManager.shared.currentProvider
        let response = try await provider.process(prompt: preset.prompt, text: context.selection.text)
        return .keepVisible(.showContent(
            Canvas.build {
                Canvas.text(response)
                Canvas.hstack(spacing: 6) {
                    Canvas.button("Replace", icon: .symbol("arrow.triangle.2.circlepath"), handler: .effect(.paste(response)))
                    Canvas.button("Copy", icon: .symbol("doc.on.doc"), handler: .effect(.copy(response)))
                }
            },
            CanvasHeader(
                title: displayTitle(using: ActionCustomizationManager.shared),
                icon: icon.symbolName
            )
        ))
    }

    @MainActor
    private func preset() -> AIActionPreset? {
        AIServiceManager.shared.presets.first { $0.id == presetID }
    }
}
