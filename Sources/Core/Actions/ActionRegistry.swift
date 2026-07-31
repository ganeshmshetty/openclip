import Foundation

@MainActor
public final class ActionRegistry: Sendable {
    public static let shared = ActionRegistry()
    
    public private(set) var actions: [any Action] = []
    
    private init() {
        registerBuiltInActions()
    }
    
    private func registerBuiltInActions() {
        actions = [
            CopyAction(),
            CutAction(),
            PasteAction(),
            SearchAction(),
            OpenURLAction(),
            ServicesAction()
        ]
    }
    
    public func register(action: any Action) {
        actions.append(action)
    }
    
    public func availableActions(for context: ActionContext) -> [any Action] {
        return actions.filter { $0.isEnabled(for: context) }
    }
}
