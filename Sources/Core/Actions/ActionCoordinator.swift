// ActionCoordinator.swift
// OpenClip
//
// Composition root that connects builtin actions, custom actions, and extensions to the central
// ActionRegistry. Wires the onRegister/onUnregister callbacks that CustomActionManager and
// ExtensionManager use to report changes, so neither manager touches ActionRegistry directly.
import Foundation
import Combine

/// Deep module unifying action discovery, extension scanning, app rule filtering, and user layout ordering.
@MainActor
public final class ActionCoordinator: ObservableObject, Sendable {
    public static let shared = ActionCoordinator()
    
    @Published public private(set) var actions: [any Action] = []
    
    private let registry = ActionRegistry.shared
    private let ruleEngine = RuleEngine.shared
    private let extensionManager = ExtensionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    internal init() {
        registry.$actions
            .assign(to: &$actions)
    }
    
    public func loadInitialState() async {
        // Wire the managers to the registry through callbacks — they never touch
        // ActionRegistry.shared directly.
        CustomActionManager.shared.onRegister = { [registry] action in
            registry.register(action: action)
        }
        CustomActionManager.shared.onUnregister = { [registry] actionID in
            registry.unregister(actionID: actionID)
        }
        ExtensionManager.shared.onRegister = { [registry] action in
            registry.register(action: action)
        }
        ExtensionManager.shared.onUnregister = { [registry] actionID in
            registry.unregister(actionID: actionID)
        }

        // 1. Core builtins
        let coreBuiltins = BuiltinRegistry.makeCoreBuiltins()
        registry.register(builtIns: coreBuiltins)
        
        // 2. Custom actions saved by user
        CustomActionManager.shared.load()
        
        // 3. Disk extensions & app rules
        await ruleEngine.loadRules(from: Constants.rulesFileURL)
        await extensionManager.loadExtensions()
    }
    
    public func resolveActions(for context: ActionContext) -> [any Action] {
        let bundleID = context.selection.sourceApp.bundleIdentifier ?? ""
        let policy = ruleEngine.resolvePolicies(for: bundleID)
        var updatedSelection = context.selection
        if policy.denyFormatting || policy.assumePaste || policy.grabPasteboard {
            updatedSelection = SelectionContext(
                text: context.selection.text,
                sourceApp: context.selection.sourceApp,
                cursorPosition: context.selection.cursorPosition,
                mouseDownLocation: context.selection.mouseDownLocation,
                selectionBounds: context.selection.selectionBounds,
                timestamp: context.selection.timestamp,
                appPolicy: policy
            )
        }
        let updatedContext = ActionContext(selection: updatedSelection, modifiers: context.modifiers)
        return registry.availableActions(for: updatedContext)
    }
    
    public func register(action: any Action) {
        registry.register(action: action)
    }
    
    public func unregister(actionID: String) {
        registry.unregister(actionID: actionID)
    }
    
    public func moveActions(from source: IndexSet, to destination: Int) {
        registry.moveActions(from: source, to: destination)
    }
}
