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
            // Keep original order if neither is in the order array
            if idxA == Int.max && idxB == Int.max {
                return false
            }
            return idxA < idxB
        }
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
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        let defaultDisabledSubActions = TransformCase.defaultDisabledActionIDs
        let configuredDisabled = settingsStore.get(.disabledActionIDs)
        var disabledIDs = configuredDisabled.isEmpty ? Set(defaultDisabledSubActions) : configuredDisabled
        if !settingsStore.get(.isTransformGroupEnabled) {
            disabledIDs.insert("builtin.transform")
        }
        return actions.filter { action in
            if disabledIDs.contains(action.id) {
                return false
            }
            if context.selection.appPolicy.denyFormatting && action.isFormatting {
                return false
            }
            return action.isEnabled(for: context)
        }
    }
}

