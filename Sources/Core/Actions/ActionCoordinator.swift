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
    @Published public private(set) var actionGroupDefs: [ActionGroupDef] = []
    
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
        rulesURL: URL = Constants.rulesFileURL,
        dictionaryLookup: @escaping @Sendable (String) -> String? = { _ in nil }
    ) async {
        // Wire the extension manager to the registry through callbacks — it never touches
        // ActionRegistry directly.
        extensionManager.onRegister = { [registry] action in
            registry.register(action: action)
        }
        extensionManager.onUnregister = { [weak self, registry] actionID in
            registry.unregister(actionID: actionID)
            self?.pruneGroups(removing: actionID)
        }

        // 1. Core builtins
        let coreBuiltins = BuiltinRegistry.makeCoreBuiltins(
            settingsStore: settingsStore,
            dictionaryLookup: dictionaryLookup
        )
        registry.register(builtIns: coreBuiltins)
        
        // 2. Disk extensions (manifests, standalone scripts, snippets) & app rules
        await ruleEngine.loadRules(from: rulesURL)
        await extensionManager.loadExtensions(from: extensionsDirectory)

        // 3. Custom action groups
        loadGroupDefs()
    }
    
    public func resolveActions(for context: ActionContext) -> [any Action] {
        registry.availableActions(for: context)
    }

    /// Catalog for the action-search palette, filtered to actions that can perform given `context`.
    /// Settings-disabled actions remain visible; contextually-unable ones (no selection, regex/app
    /// gate, clipboard fallback) are dropped.
    public func searchCatalog(for context: ActionContext) -> [any Action] {
        registry.searchCatalog(for: context)
    }
    
    public func register(action: any Action) {
        registry.register(action: action)
    }
    
    public func unregister(actionID: String) {
        registry.unregister(actionID: actionID)
        pruneGroups(removing: actionID)
    }
    
    public func moveActions(from source: IndexSet, to destination: Int) {
        registry.moveActions(from: source, to: destination)
        syncGroupMemberOrder()
    }

    private func syncGroupMemberOrder() {
        guard !actionGroupDefs.isEmpty else { return }
        let currentOrder = registry.actions.map(\.id)
        let orderIndexMap: [String: Int] = Dictionary(
            currentOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var changed = false
        var updated = actionGroupDefs
        for i in 0..<updated.count {
            let sortedMembers = updated[i].memberActionIDs.sorted { idA, idB in
                let rankA = orderIndexMap[idA] ?? Int.max
                let rankB = orderIndexMap[idB] ?? Int.max
                return rankA < rankB
            }
            if sortedMembers != updated[i].memberActionIDs {
                updated[i].memberActionIDs = sortedMembers
                changed = true
            }
        }
        if changed {
            actionGroupDefs = updated
            saveAndApplyGroupDefs()
        }
    }

    // MARK: - Custom Action Groups

    public func loadGroupDefs() {
        let data = settingsStore.get(.actionGroups)
        var defs = ActionGroupDef.decodeOrEmpty(from: data)
        let pruned = pruneOrphans(in: defs)
        if pruned != defs {
            defs = pruned
            saveGroupDefs(defs)
        }
        actionGroupDefs = defs
        registry.setGroupDefs(actionGroupDefs)
    }

    private func pruneOrphans(in defs: [ActionGroupDef]) -> [ActionGroupDef] {
        let active = registry.registeredActionIDs
        guard !active.isEmpty, !defs.isEmpty else { return defs }
        return defs.compactMap { def -> ActionGroupDef? in
            var copy = def
            copy.memberActionIDs.removeAll { !active.contains($0) }
            return copy.memberActionIDs.count >= 2 ? copy : nil
        }
    }

    private func pruneGroups(removing actionID: String) {
        var updated: [ActionGroupDef] = []
        var changed = false
        for var def in actionGroupDefs {
            if def.memberActionIDs.contains(actionID) {
                def.memberActionIDs.removeAll { $0 == actionID }
                changed = true
                if def.memberActionIDs.count >= 2 {
                    updated.append(def)
                }
            } else {
                updated.append(def)
            }
        }
        if changed {
            actionGroupDefs = updated
            saveAndApplyGroupDefs()
        }
    }

    public func createGroup(title: String, iconName: String, memberActionIDs: [String]) {
        var seen = Set<String>()
        var deduped: [String] = []
        for rawID in memberActionIDs {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }
        guard deduped.count >= 2 else { return }

        // Remove members from existing groups
        let memberSet = Set(deduped)
        var updated: [ActionGroupDef] = []
        for var def in actionGroupDefs {
            def.memberActionIDs.removeAll { memberSet.contains($0) }
            if def.memberActionIDs.count >= 2 {
                updated.append(def)
            }
        }

        let newID = "vgroup.\(UUID().uuidString.prefix(8).lowercased())"
        let newDef = ActionGroupDef(id: newID, title: title, iconName: iconName, memberActionIDs: deduped)
        updated.append(newDef)
        actionGroupDefs = updated
        saveAndApplyGroupDefs()
    }

    public func updateGroup(groupID: String, title: String, iconName: String, memberActionIDs: [String]) {
        guard let index = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        var seen = Set<String>()
        var deduped: [String] = []
        for rawID in memberActionIDs {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }
        if deduped.count < 2 {
            ungroup(groupID: groupID)
            return
        }
        actionGroupDefs[index].title = title
        actionGroupDefs[index].iconName = iconName
        actionGroupDefs[index].memberActionIDs = deduped
        saveAndApplyGroupDefs()
    }

    public func addToGroup(actionID: String, groupID: String, atIndex: Int? = nil) {
        guard let groupIndex = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        let trimmedID = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        // Remove action from any other existing group
        var updated = actionGroupDefs
        for i in 0..<updated.count {
            if updated[i].id != groupID && updated[i].memberActionIDs.contains(trimmedID) {
                updated[i].memberActionIDs.removeAll { $0 == trimmedID }
            }
        }
        // Auto-disband any other groups that dropped below 2 members
        updated = updated.filter { $0.id == groupID || $0.memberActionIDs.count >= 2 }

        guard let targetIndex = updated.firstIndex(where: { $0.id == groupID }) else { return }
        var members = updated[targetIndex].memberActionIDs
        members.removeAll { $0 == trimmedID }
        if let atIndex, atIndex >= 0 && atIndex <= members.count {
            members.insert(trimmedID, at: atIndex)
        } else {
            members.append(trimmedID)
        }
        updated[targetIndex].memberActionIDs = members
        actionGroupDefs = updated
        saveAndApplyGroupDefs()
    }

    public func ungroup(groupID: String) {
        actionGroupDefs.removeAll { $0.id == groupID }
        saveAndApplyGroupDefs()
    }

    public func removeFromGroup(actionID: String, groupID: String) {
        guard let index = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        actionGroupDefs[index].memberActionIDs.removeAll { $0 == actionID }
        if actionGroupDefs[index].memberActionIDs.count < 2 {
            actionGroupDefs.remove(at: index)
        }
        saveAndApplyGroupDefs()
    }

    public func reset() {
        actionGroupDefs = []
        registry.setGroupDefs([])
        settingsStore.set(.actionGroups, value: nil)
    }

    private func saveGroupDefs(_ defs: [ActionGroupDef]) {
        let data = try? ActionGroupDef.encode(defs)
        settingsStore.set(.actionGroups, value: data)
    }

    private func saveAndApplyGroupDefs() {
        saveGroupDefs(actionGroupDefs)
        registry.setGroupDefs(actionGroupDefs)
    }
}
