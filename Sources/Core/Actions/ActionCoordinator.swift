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
        extensionManager.onUnregister = { [registry] actionID in
            registry.unregister(actionID: actionID)
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

        // 3. First-class custom actions
        loadCustomActions()

        // 4. Custom action groups
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
    }

    public func replaceActions(matching isMatch: @escaping (any Action) -> Bool, with newActions: [any Action]) {
        registry.replaceRegisteredActions(matching: isMatch, with: newActions)
        self.actions = registry.actions
        syncGroupMemberOrder()
    }
    
    public func moveActions(from source: IndexSet, to destination: Int) {
        registry.moveActions(from: source, to: destination)
        syncGroupMemberOrder()
    }

    public func setExtensionGroupMemberOrder(groupID: String, memberIDs: [String]) {
        registry.setExtensionGroupMemberOrder(groupID: groupID, memberIDs: memberIDs)
        self.actions = registry.actions
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

        let sortedDefs = updated.sorted { defA, defB in
            let rankA = orderIndexMap[defA.id] ?? Int.max
            let rankB = orderIndexMap[defB.id] ?? Int.max
            return rankA < rankB
        }
        if sortedDefs != updated {
            updated = sortedDefs
            changed = true
        }

        if changed {
            actionGroupDefs = updated
            saveAndApplyGroupDefs()
        }
    }

    // MARK: - Custom Actions

    public private(set) var customActions: [CustomAction] = []

    public func loadCustomActions() {
        if let data = settingsStore.get(.customActions),
           let decoded = try? JSONDecoder().decode([CustomAction].self, from: data) {
            self.customActions = decoded
        } else {
            self.customActions = []
        }
        for action in customActions {
            registry.register(action: action)
        }
    }

    public func saveCustomAction(_ action: CustomAction) {
        var updated = customActions
        if let idx = updated.firstIndex(where: { $0.id == action.id }) {
            updated[idx] = action
        } else {
            updated.append(action)
        }
        persistCustomActions(updated)
        registry.register(action: action)
        self.actions = registry.actions
        syncGroupMemberOrder()
    }

    public func deleteCustomAction(actionID: String) {
        var updated = customActions
        updated.removeAll(where: { $0.id == actionID })
        persistCustomActions(updated)
        registry.unregister(actionID: actionID)
        var disabled = settingsStore.get(.disabledActionIDs)
        if disabled.contains(actionID) {
            disabled.remove(actionID)
            settingsStore.set(.disabledActionIDs, value: disabled)
        }
        self.actions = registry.actions
        syncGroupMemberOrder()
    }

    @discardableResult
    public func duplicateCustomAction(actionID: String) -> CustomAction? {
        guard let original = customActions.first(where: { $0.id == actionID }) else {
            return nil
        }
        let newID = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        let override = ActionCustomizationManager.shared.override(for: actionID)
        let baseTitle = override?.customTitle ?? original.title
        let baseIcon = override?.customIconSymbol ?? original.iconName
        let copyTitle = "\(baseTitle) Copy"

        let duplicated = CustomAction(
            id: newID,
            title: copyTitle,
            iconName: baseIcon,
            type: original.type,
            chrome: original.chrome,
            rules: original.rules
        )

        saveCustomAction(duplicated)
        insertActionOrderAfter(newID: newID, originalID: actionID)

        for def in actionGroupDefs {
            if let idx = def.memberActionIDs.firstIndex(of: actionID) {
                addToGroup(actionID: newID, groupID: def.id, atIndex: idx + 1)
                break
            }
        }

        return duplicated
    }

    public func insertActionOrderAfter(newID: String, originalID: String) {
        var order = settingsStore.get(.actionOrder)
        if order.isEmpty {
            order = registry.actions.map(\.id)
        }
        order.removeAll(where: { $0 == newID })
        if let idx = order.firstIndex(of: originalID) {
            order.insert(newID, at: idx + 1)
        } else {
            order.append(newID)
        }
        settingsStore.set(.actionOrder, value: order)
        registry.sortActions()
        self.actions = registry.actions
        syncGroupMemberOrder()
    }

    private func persistCustomActions(_ actions: [CustomAction]) {
        self.customActions = actions
        if let encoded = try? JSONEncoder().encode(actions) {
            settingsStore.set(.customActions, value: encoded)
        }
    }

    // MARK: - Custom Action Groups

    public func loadGroupDefs() {
        let data = settingsStore.get(.actionGroups)
        let defs = ActionGroupDef.decodeOrEmpty(from: data)
        actionGroupDefs = defs
        registry.setGroupDefs(actionGroupDefs)
    }

    private var extensionGroupPackageIDs: Set<String> {
        Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions }
                .compactMap { ActionIdentity.extensionPackageID(of: $0) }
        )
    }

    private func isBelongingToExtensionGroupPackage(_ action: any Action) -> Bool {
        guard let pkgID = ActionIdentity.extensionPackageID(of: action) else { return false }
        return extensionGroupPackageIDs.contains(pkgID)
    }

    public func isEligibleForGrouping(actionID: String) -> Bool {
        guard let action = actions.first(where: { $0.id == actionID }) else { return false }
        if actionGroupDefs.contains(where: { $0.id == actionID }) { return false }
        guard ActionIdentity.isEligibleForGrouping(action) else { return false }
        guard !isBelongingToExtensionGroupPackage(action) else { return false }
        return true
    }

    /// Returns the new group's id, or nil when nothing eligible was left to put in it — an empty
    /// group is not kept (see `saveAndApplyGroupDefs`).
    @discardableResult
    public func createGroup(title: String, iconName: String, memberActionIDs: [String] = []) -> String? {
        var seen = Set<String>()
        var deduped: [String] = []
        for rawID in memberActionIDs {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty && isEligibleForGrouping(actionID: id) else { continue }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }

        // Remove members from existing groups
        let memberSet = Set(deduped)
        var updated: [ActionGroupDef] = []
        for var def in actionGroupDefs {
            def.memberActionIDs.removeAll { memberSet.contains($0) }
            updated.append(def)
        }

        let newID = "vgroup.\(UUID().uuidString.prefix(8).lowercased())"
        let resolvedIcon = iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : iconName
        let newDef = ActionGroupDef(id: newID, title: title, iconName: resolvedIcon, memberActionIDs: deduped)
        updated.append(newDef)
        actionGroupDefs = updated
        saveAndApplyGroupDefs()
        return actionGroupDefs.contains(where: { $0.id == newID }) ? newID : nil
    }

    private func isEligible(actionID: String, forGroup groupID: String, existingMembers: Set<String>) -> Bool {
        let trimmed = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != groupID && !trimmed.hasPrefix("vgroup.") else { return false }
        guard trimmed != "builtin.ai_tools" && trimmed != "builtin.completion" else { return false }
        if actionGroupDefs.contains(where: { $0.id == trimmed }) { return false }
        for def in actionGroupDefs where def.id != groupID {
            if def.memberActionIDs.contains(trimmed) { return false }
        }

        if let action = actions.first(where: { $0.id == trimmed }) {
            guard ActionIdentity.isEligibleForGrouping(action) else { return false }
            guard !isBelongingToExtensionGroupPackage(action) else { return false }
            return true
        }

        // An unresolved action ID is accepted only when it already belongs to the group being edited
        return existingMembers.contains(trimmed)
    }

    public func updateGroup(groupID: String, title: String, iconName: String, memberActionIDs: [String]) {
        guard let index = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        let existingMembers = Set(actionGroupDefs[index].memberActionIDs)
        var seen = Set<String>()
        var deduped: [String] = []
        for rawID in memberActionIDs {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty && isEligible(actionID: id, forGroup: groupID, existingMembers: existingMembers) else { continue }
            if seen.insert(id).inserted {
                deduped.append(id)
            }
        }
        let resolvedIcon = iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : iconName
        actionGroupDefs[index].title = title
        actionGroupDefs[index].iconName = resolvedIcon
        actionGroupDefs[index].memberActionIDs = deduped
        saveAndApplyGroupDefs()
        syncCatalogOrder(for: groupID, memberIDs: deduped)
    }

    private func syncCatalogOrder(for groupID: String, memberIDs: [String]) {
        guard !memberIDs.isEmpty else { return }
        var currentActions = registry.actions
        guard let _ = currentActions.firstIndex(where: { $0.id == groupID }) else { return }

        let memberSet = Set(memberIDs)
        let actionMap = Dictionary(currentActions.filter { memberSet.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        currentActions.removeAll { memberSet.contains($0.id) }

        guard let newGroupIndex = currentActions.firstIndex(where: { $0.id == groupID }) else { return }
        let orderedMembers = memberIDs.compactMap { actionMap[$0] }
        currentActions.insert(contentsOf: orderedMembers, at: newGroupIndex + 1)

        let newOrder = currentActions.map(\.id)
        settingsStore.set(.actionOrder, value: newOrder)
        registry.setGroupDefs(actionGroupDefs)
    }

    public func addToGroup(actionID: String, groupID: String, atIndex: Int? = nil) {
        guard let _ = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        let trimmedID = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        guard isEligibleForGrouping(actionID: trimmedID) else { return }
        guard trimmedID != groupID else { return }

        // Remove action from any other existing group
        var updated = actionGroupDefs
        for i in 0..<updated.count {
            if updated[i].id != groupID && updated[i].memberActionIDs.contains(trimmedID) {
                updated[i].memberActionIDs.removeAll { $0 == trimmedID }
            }
        }

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

    public func memberActionIDs(for groupID: String) -> [String] {
        if let def = actionGroupDefs.first(where: { $0.id == groupID }) {
            return def.memberActionIDs
        }
        guard let groupAction = actions.first(where: { $0.id == groupID }) else { return [] }
        if let provider = groupAction as? any SubActionProviding {
            return provider.subActions(in: actions).map(\.id)
        }
        return actions.filter { $0.id != groupID && $0.id.hasPrefix(groupID + ".") }.map(\.id)
    }

    public func ungroup(groupID: String) {
        actionGroupDefs.removeAll { $0.id == groupID }
        saveAndApplyGroupDefs()
    }

    public func removeFromGroup(actionID: String, groupID: String) {
        guard let index = actionGroupDefs.firstIndex(where: { $0.id == groupID }) else { return }
        actionGroupDefs[index].memberActionIDs.removeAll { $0 == actionID }
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
        for i in 0..<actionGroupDefs.count {
            let groupID = actionGroupDefs[i].id
            let existingMembers = Set(actionGroupDefs[i].memberActionIDs)
            actionGroupDefs[i].memberActionIDs = actionGroupDefs[i].memberActionIDs.filter {
                isEligible(actionID: $0, forGroup: groupID, existingMembers: existingMembers)
            }
        }
        // A group is a container for actions, so an empty one is a row in the popup bar that opens
        // onto nothing: taking the last action out of a group takes the group with it, however it
        // left — dragged to the top level, dragged into another group, or deleted outright.
        //
        // Only mutations come through here. `loadGroupDefs` deliberately does not, so a group whose
        // members have not been registered yet survives launch.
        actionGroupDefs.removeAll { $0.memberActionIDs.isEmpty }
        saveGroupDefs(actionGroupDefs)
        registry.setGroupDefs(actionGroupDefs)
    }
}
