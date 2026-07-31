import Foundation

@MainActor
public final class ActionRegistry: Sendable {
    public static let shared = ActionRegistry()
    
    public private(set) var actions: [any Action] = []
    
    private init() {
    }
    
    public func register(builtIns: [any Action]) {
        actions.append(contentsOf: builtIns)
    }
    
    public func register(action: any Action) {
        actions.append(action)
    }
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        return actions.filter { action in
            if context.selection.appPolicy.denyFormatting && action.isFormatting {
                return false
            }
            return action.isEnabled(for: context)
        }
    }
}
