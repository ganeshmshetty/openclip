// ActionRegistry.swift
// OpenClip
//
// Stores and orders all registered actions, providing a reactive catalog of available text manipulations.
// Interacts with the Settings Door to respect user sorting preferences and enable dynamic action lookup by identifier.
import Foundation
import Combine

@MainActor
public final class ActionRegistry: ObservableObject, Sendable {
    public static let shared = ActionRegistry()
    
    @Published public private(set) var actions: [any Action] = []
    private let settingsStore: SettingsStore
    
    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
    public func register(builtIns: [any Action]) {
        // Dedupe against existing actions and against earlier entries within the same batch,
        // so repeated loadInitialState() calls or a duplicate entry in the catalog don't append twice.
        var seenIDs = Set(actions.map(\.id))
        actions.append(contentsOf: builtIns.filter { action in
            guard !seenIDs.contains(action.id) else { return false }
            seenIDs.insert(action.id)
            return true
        })
        sortActions()
    }
    
    public func register(action: any Action) {
        // Replace if ID already exists, otherwise append
        if let idx = actions.firstIndex(where: { $0.id == action.id }) {
            actions[idx] = action
        } else {
            actions.append(action)
        }
        sortActions()
    }
    
    private func sortActions() {
        let order = settingsStore.get(.actionOrder)
        actions.sort { a, b in
            let idxA = order.firstIndex(of: a.id) ?? Int.max
            let idxB = order.firstIndex(of: b.id) ?? Int.max
            // Default slot for un-ordered actions: a builtin (e.g. the AI Tools launcher) joins
            // the far end of the builtin group — right after the last ordered builtin, ahead of
            // un-ordered extensions/AI presets — instead of the absolute tail. Without this, a
            // newly added builtin sorts after installed extensions whenever `.actionOrder` is
            // populated but omits it.
            if idxA == Int.max && idxB == Int.max {
                let aIsBuiltin = builtinSource(a)
                let bIsBuiltin = builtinSource(b)
                if aIsBuiltin != bIsBuiltin {
                    return aIsBuiltin && !bIsBuiltin
                }
                // Same group (both ordered-equivalent): keep registry-relative order. Not a
                // strict guarantee (Swift sort is unstable) but membership filtering downstream
                // is order-agnostic.
                return false
            }
            return idxA < idxB
        }
    }

    private func builtinSource(_ action: any Action) -> Bool {
        ActionIdentity.isBuiltin(action)
    }
    
    public func moveActions(from source: IndexSet, to destination: Int) {
        var newActions = actions
        let movingActions = source.map { newActions[$0] }
        for index in source.reversed() {
            newActions.remove(at: index)
        }
        
        var dest = destination
        for idx in source {
            if idx < destination {
                dest -= 1
            }
        }
        
        newActions.insert(contentsOf: movingActions, at: dest)
        actions = newActions
        
        let newOrder = actions.map { $0.id }
        settingsStore.set(.actionOrder, value: newOrder)
    }
    
    public func unregister(actionID: String) {
        actions.removeAll(where: { $0.id == actionID })
    }

    /// Clears all registered actions. Test-isolation hook so the shared singleton does not leak
    /// state across test cases.
    public func reset() {
        actions = []
    }
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)

        func passes(_ action: any Action) -> Bool {
            // AI preset actions are never bar rows: the reorderable `builtin.aiTools` action
            // (chrome.launchesAI) is the popup's AI entry, so presets must not flood the
            // paginated bar even when enabled.
            if ActionIdentity.isAIPreset(action) {
                return false
            }
            // Clipboard fallback is not a live selection: Copy/Cut (and any future action that
            // reads or mutates the real selection) must not act on text that was never selected.
            if context.selection.isClipboardFallback && action.chrome.requiresLiveSelection {
                return false
            }
            if disabledIDs.contains(action.id) {
                return false
            }
            // Whole-package disable: an action whose chrome source names a disabled package
            // is hidden before per-action visibility runs.
            if let packageID = ActionIdentity.extensionPackageID(of: action), disabledPackages.contains(packageID) {
                return false
            }
            if context.selection.appPolicy.denyFormatting && action.isFormatting {
                return false
            }
            return action.isEnabled(for: context)
        }

        // Group sub-actions are only reachable through their group's sub-menu. A group whose
        // row is disabled (or otherwise not visible) hides its sub-actions entirely, so a
        // disabled group never leaks its sub-actions into the bar.
        let groupRowIDs = actions
            .filter { $0.chrome.popupBehavior == .showSubActions }
            .map { $0.id }
        let enabledGroupIDs = Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions }
                .filter(passes)
                .map { $0.id }
        )

        return actions.filter { action in
            guard passes(action) else { return false }
            if let groupID = groupRowIDs.first(where: { action.id.hasPrefix($0 + ".") }),
               !enabledGroupIDs.contains(groupID) {
                return false
            }
            return true
        }
    }

    /// The full registered catalog for the action-search palette: every registered action
    /// regardless of enable state, minus the inline completion pseudo-action. No enable/disable,
    /// context, or group filtering — sub-actions appear individually, flat. Group rows remain
    /// (their sub-actions are now reachable directly from the palette).
    public var searchCatalog: [any Action] {
        actions.filter { !$0.chrome.launchesAI && !ActionIdentity.isCompletionPseudoAction($0) }
    }
}

