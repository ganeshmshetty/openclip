// AIToolsAction.swift
// OpenClip
//
// The "AI Tools" bar launcher, modeled as a normal reorderable builtin action so users can
// position it among their other bar actions. Never a search-palette entry (chrome.launchesAI is
// excluded in `ActionRegistry.searchCatalog`); the popup bar routes its click into AI mode via
// `chrome.launchesAI` instead of `perform`. Its enable state is single-sourced to
// `AIServiceManager.isAIEnabled`, which the AI-tab and Actions-tab toggles share.
import Foundation
import Core

public struct AIToolsAction: Action, SubActionProviding {
    public init() {}

    public var id: String { "builtin.aiTools" }
    public var title: String { String(localized: "AI Tools") }
    public var icon: ActionIcon { .symbol(Constants.defaultAIIconSymbol) }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        AIServiceManager.shared.isAIEnabled
    }

    /// Defensive fallback: the bar routes via `chrome.launchesAI` and the palette excludes this
    /// action, so `perform` is never the entry point (same contract as `AIAction`).
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }

    // The AI Tools launcher's sub-actions are the registered AI presets (chrome source `.ai`).
    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        let presets = catalog.filter { action in
            ActionIdentity.isAIPreset(action)
        }
        if !presets.isEmpty {
            return presets
        }
        return AIServiceManager.shared.enabledPresets.map { preset in
            AIAction(presetID: preset.id, title: preset.title)
        }
    }
}
