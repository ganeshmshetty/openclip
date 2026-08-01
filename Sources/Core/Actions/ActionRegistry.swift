import Foundation
import Combine

@MainActor
public final class ActionRegistry: ObservableObject, Sendable {
    public static let shared = ActionRegistry()
    
    @Published public private(set) var actions: [any Action] = []
    
    private init() {
    }
    
    public func register(builtIns: [any Action]) {
        actions.append(contentsOf: builtIns)
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
        let order = UserDefaults.standard.stringArray(forKey: "action.order") ?? []
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
        UserDefaults.standard.set(newOrder, forKey: "action.order")
    }
    
    public func unregister(actionID: String) {
        actions.removeAll(where: { $0.id == actionID })
    }
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        let defaultEnabledTransformCases: Set<TransformCase> = [.uppercase, .lowercase, .titleCase, .camelCase, .trimWhitespace, .formatJSON]
        let defaultDisabledSubActions = ["builtin.airdrop"] + TransformCase.allCases
            .filter { !defaultEnabledTransformCases.contains($0) }
            .map { "builtin.transform.\($0.rawValue)" }
        var disabledIDs = Set(UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey) ?? defaultDisabledSubActions)
        if !UserDefaults.standard.bool(forKey: "action.airdrop.enabled") {
            disabledIDs.insert("builtin.airdrop")
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
