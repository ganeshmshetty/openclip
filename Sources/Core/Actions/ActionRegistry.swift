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
    }
    
    public func register(action: any Action) {
        // Replace if ID already exists, otherwise append
        if let idx = actions.firstIndex(where: { $0.id == action.id }) {
            actions[idx] = action
        } else {
            actions.append(action)
        }
    }
    
    public func unregister(actionID: String) {
        actions.removeAll(where: { $0.id == actionID })
    }
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        let disabledIDs = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey) ?? []
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
