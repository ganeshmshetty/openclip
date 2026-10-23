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
    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }

    public var id: String { "builtin.aiTools" }
    public var title: String { String(localized: "AI Tools") }
    public var icon: ActionIcon { .symbol(Constants.defaultAIIconSymbol) }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        settingsStore.get(.isAIEnabled)
    }

    /// Defensive fallback: the bar routes via `chrome.launchesAI` and the palette excludes this
    /// action, so `perform` is never the entry point (same contract as `AIAction`).
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }

    // The AI Tools launcher's sub-actions are the registered AI presets (chrome source `.ai`) that the
    // user hasn't moved out, in the order arranged on the Actions page (#175). Ordering by the stored
    // member list, not by catalog position, keeps the hover sub-bar and the click palette in sync with
    // Preferences even when a surface reorders its catalog (e.g. contextual matches first).
    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        let standaloneIDs = settingsStore.get(.standaloneAIActionIDs)
        let members = catalog.filter { action in
            ActionIdentity.isAIPreset(action) && !standaloneIDs.contains(action.id)
        }
        let arranged = settingsStore.get(.extensionGroupMemberOrder)[id] ?? []
        guard !arranged.isEmpty else { return members }
        let rank = Dictionary(arranged.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return members.enumerated()
            .sorted { lhs, rhs in
                let l = rank[lhs.element.id] ?? Int.max, r = rank[rhs.element.id] ?? Int.max
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
