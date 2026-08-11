// ActionCoordinator.swift
// OpenClip
//
// Composition root that connects builtin actions and disk extensions to the central
// ActionRegistry. Wires the onRegister/onUnregister callbacks that ExtensionManager
// uses to report changes, so the manager never touches ActionRegistry directly.
import Foundation
import Combine

/// Deep module unifying action discovery, extension scanning, app rule filtering, and user layout ordering.
@MainActor
public final class ActionCoordinator: ObservableObject, Sendable {
    public static let shared = ActionCoordinator()
    
    @Published public private(set) var actions: [any Action] = []
    
    private let registry: ActionRegistry
    private let ruleEngine: RuleEngine
    private let extensionManager: ExtensionManager
    private let settingsStore: any SettingsStore
    private var cancellables = Set<AnyCancellable>()
    
    internal init(
        registry: ActionRegistry = .shared,
        ruleEngine: RuleEngine = .shared,
        extensionManager: ExtensionManager = .shared,
        settingsStore: any SettingsStore = DefaultSettingsStore.shared
    ) {
        self.registry = registry
        self.ruleEngine = ruleEngine
        self.extensionManager = extensionManager
        self.settingsStore = settingsStore
        registry.$actions
            .assign(to: &$actions)
    }
    
    public func loadInitialState(
        extensionsDirectory: URL = Constants.extensionsDirectory,
        rulesURL: URL = Constants.rulesFileURL
    ) async {
        // Wire the extension manager to the registry through callbacks — it never touches
        // ActionRegistry directly.
        extensionManager.onRegister = { [registry] action in
            registry.register(action: action)
        }
        extensionManager.onUnregister = { [registry] actionID in
            registry.unregister(actionID: actionID)
        }

        // 1. Core builtins
        let coreBuiltins = BuiltinRegistry.makeCoreBuiltins(settingsStore: settingsStore)
        registry.register(builtIns: coreBuiltins)
        
        // 2. Disk extensions (manifests, standalone scripts, snippets) & app rules
        await ruleEngine.loadRules(from: rulesURL)
        await extensionManager.loadExtensions(from: extensionsDirectory)
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
                appPolicy: policy,
                isClipboardFallback: context.selection.isClipboardFallback
            )
        }
        let updatedContext = ActionContext(selection: updatedSelection, modifiers: context.modifiers)
        return registry.availableActions(for: updatedContext)
    }

    /// Catalog for the action-search palette, filtered to actions that can perform given `context`.
    /// Settings-disabled actions remain visible; contextually-unable ones (no selection, regex/app
    /// gate, clipboard fallback, formatting policy) are dropped.
    public func searchCatalog(for context: ActionContext) -> [any Action] {
        registry.searchCatalog(for: resolvedContext(for: context))
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
