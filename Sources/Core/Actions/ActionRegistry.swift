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
    private var registeredActions: [any Action] = []
    private var groupDefs: [ActionGroupDef] = []
    private let settingsStore: SettingsStore
    
    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
    public func register(builtIns: [any Action]) {
        // Dedupe against existing and earlier batch entries so repeated loads never append twice.
        var seenIDs = Set(registeredActions.map(\.id))
        registeredActions.append(contentsOf: builtIns.filter { action in
            guard !seenIDs.contains(action.id) else { return false }
            seenIDs.insert(action.id)
            return true
        })
        sortActions()
    }
    
    public func register(action: any Action) {
        if let idx = registeredActions.firstIndex(where: { $0.id == action.id }) {
            registeredActions[idx] = action
        } else {
            registeredActions.append(action)
        }
        sortActions()
    }
    
    /// Maps each sub-action to its provider row (`SubActionProviding`) so `sortActions` keeps children with their parent.
    /// An explicit `action.order` entry outranks inheritance for non-group providers. First claim wins; one level only.
    private func subActionParents(explicitlyOrderedIDs: [String: Int]) -> [String: String] {
        let resolver = SubActionResolver()
        let standaloneAIIDs = settingsStore.get(.standaloneAIActionIDs)
        var parents: [String: String] = [:]
        for parent in registeredActions where parent is any SubActionProviding {
            for child in resolver.subActions(of: parent, in: registeredActions) {
                guard child.id != parent.id, parents[child.id] == nil else { continue }
                if ActionIdentity.isAIPreset(child), standaloneAIIDs.contains(child.id) { continue }
                if !(parent is GroupAction), explicitlyOrderedIDs[child.id] != nil {
                    continue
                }
                parents[child.id] = parent.id
            }
        }
        return parents
    }

    public func sortActions() {
        let order = settingsStore.get(.actionOrder)
        let orderIndexMap: [String: Int] = Dictionary(
            order.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Flat surfaces (the search palette) list children instead of their parent row, so a child that
        // inherits nothing would sort last. AI presets (chrome source `.ai`) are the visible case.
        let parentIDByChildID = subActionParents(explicitlyOrderedIDs: orderIndexMap)
        let actionsByID = Dictionary(registeredActions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let extensionMemberOrder = settingsStore.get(.extensionGroupMemberOrder)

        // Tier classification:
        // Tier 0: Explicitly ordered by user in `action.order` (sorted by rank in orderIndexMap)
        // Tier 1: Un-ordered built-in actions (sorted stably by insertion order)
        // Tier 2: Un-ordered extensions/other actions (sorted stably by insertion order)
        // A child adopts its parent's tier and rank, sorting right after it (`subRank` 1).
        func placement(of action: any Action) -> (tier: Int, rank: Int) {
            if let index = orderIndexMap[action.id] {
                return (0, index)
            } else if let packageID = ActionIdentity.extensionPackageID(of: action),
                      let index = orderIndexMap[packageID] {
                return (0, index)
            } else if let gated = action as? GatedExtensionAction,
                      let match = order.enumerated().first(where: { $0.element == gated.packageID || $0.element.hasPrefix(gated.packageID + ".") }) {
                return (0, match.offset)
            } else if ActionIdentity.isBuiltin(action) {
                return (1, 0)
            } else {
                return (2, 0)
            }
        }

        let offsetByID: [String: Int] = Dictionary(
            registeredActions.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ranked: [(action: any Action, tier: Int, rank: Int, slot: Int, subRank: Int, subOrder: Int, stableOffset: Int)] = registeredActions.enumerated().map { offset, action in
            if let parentID = parentIDByChildID[action.id],
               let parent = actionsByID[parentID],
               let parentSlot = offsetByID[parentID] {
                let inherited = placement(of: parent)
                let customSubOrder: Int
                if let groupOrder = extensionMemberOrder[parentID],
                   let memberIdx = groupOrder.firstIndex(of: action.id) {
                    customSubOrder = memberIdx
                } else {
                    customSubOrder = Int.max
                }
                return (action, inherited.tier, inherited.rank, parentSlot, 1, customSubOrder, offset)
            }
            let own = placement(of: action)
            return (action, own.tier, own.rank, offset, 0, 0, offset)
        }

        let sortedBase = ranked
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
                if lhs.subRank != rhs.subRank { return lhs.subRank < rhs.subRank }
                if lhs.subOrder != rhs.subOrder { return lhs.subOrder < rhs.subOrder }
                return lhs.stableOffset < rhs.stableOffset
            }
            .map(\.action)

        guard !groupDefs.isEmpty else {
            actions = sortedBase
            return
        }

        let allGroupedIDs = Set(groupDefs.flatMap(\.memberActionIDs))

        // Pre-collect each group's members in sorted order for contiguous injection after the header.
        var groupMembers: [String: [any Action]] = [:]
        for def in groupDefs {
            let memberSet = Set(def.memberActionIDs)
            groupMembers[def.id] = sortedBase.filter { memberSet.contains($0.id) }
        }

        var result: [any Action] = []
        var injectedGroupIDs = Set<String>()

        for action in sortedBase {
            if allGroupedIDs.contains(action.id) {
                // Inject group header + all members on first member encounter
                for def in groupDefs where !injectedGroupIDs.contains(def.id) {
                    if def.memberActionIDs.contains(action.id) {
                        injectedGroupIDs.insert(def.id)
                        result.append(CustomGroupAction(
                            id: def.id,
                            title: def.title,
                            iconName: def.iconName,
                            memberActionIDs: def.memberActionIDs
                        ))
                        if let members = groupMembers[def.id] {
                            result.append(contentsOf: members)
                        }
                        break
                    }
                }
                // Skip — already emitted during group injection above
                continue
            }
            result.append(action)
        }

        // Catch any remaining groups whose members weren't in sortedBase
        for def in groupDefs where !injectedGroupIDs.contains(def.id) {
            result.append(CustomGroupAction(
                id: def.id,
                title: def.title,
                iconName: def.iconName,
                memberActionIDs: def.memberActionIDs
            ))
        }

        actions = result
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

        let resolver = SubActionResolver()
        let subActionIDs: Set<String> = Set(
            registeredActions
                .filter { $0 is any SubActionProviding }
                .flatMap { resolver.subActions(of: $0, in: registeredActions).map(\.id) }
        )

        let standaloneAIIDs = settingsStore.get(.standaloneAIActionIDs)
        let newOrder = newActions
            .filter {
                if ActionIdentity.isAIPreset($0) { return standaloneAIIDs.contains($0.id) }
                return !($0 is CustomGroupAction) && !subActionIDs.contains($0.id)
            }
            .map { $0.id }
        settingsStore.set(.actionOrder, value: newOrder)

        // Re-derive so derived placements (sub-actions after their parent, group members) re-sort now,
        // not at the next registration.
        sortActions()
    }
    
    public func unregister(actionID: String) {
        registeredActions.removeAll(where: { $0.id == actionID })
        sortActions()
        pruneActionOrder()
    }

    public func replaceRegisteredActions(matching isMatch: (any Action) -> Bool, with newActions: [any Action]) {
        registeredActions.removeAll(where: isMatch)
        registeredActions.append(contentsOf: newActions)
        sortActions()
    }

    public func pruneActionOrder() {
        let currentOrder = settingsStore.get(.actionOrder)
        guard !currentOrder.isEmpty else { return }
        let activeIDs = Set(registeredActions.map { $0.id }).union(groupDefs.map { $0.id })
        let prunedOrder = currentOrder.filter { id in
            if activeIDs.contains(id) { return true }
            if registeredActions.contains(where: {
                if let gated = $0 as? GatedExtensionAction {
                    return gated.packageID == id || id.hasPrefix(gated.packageID + ".")
                }
                if let pkgID = ActionIdentity.extensionPackageID(of: $0) {
                    return pkgID == id
                }
                return false
            }) {
                return true
            }
            return false
        }
        if prunedOrder != currentOrder {
            settingsStore.set(.actionOrder, value: prunedOrder)
        }
    }

    public var registeredActionIDs: Set<String> {
        Set(registeredActions.map(\.id))
    }

    public func setGroupDefs(_ defs: [ActionGroupDef]) {
        self.groupDefs = defs
        sortActions()
    }

    public func setExtensionGroupMemberOrder(groupID: String, memberIDs: [String]) {
        var currentMap = settingsStore.get(.extensionGroupMemberOrder)
        currentMap[groupID] = memberIDs
        settingsStore.set(.extensionGroupMemberOrder, value: currentMap)
        sortActions()
    }

    /// Test-isolation hook: clears all registered actions so the singleton does not leak state.
    public func reset() {
        actions = []
        registeredActions = []
        groupDefs = []
    }
    
    /// Context gating shared by the bar and palette; settings-disable state is applied separately (`isDisabledInSettings`).
    private func canPerform(_ action: any Action, in context: ActionContext) -> Bool {
        // Clipboard/OCR input is not an editable source selection; OCRInputAction is the explicit exception.
        if context.selection.source == .ocr && action is any PasteRequiringAction {
            return false
        }
        if context.selection.source != .selection && action.chrome.requiresLiveSelection
            && !(context.selection.source == .ocr && action is any OCRInputAction) {
            return false
        }
        return action.isEnabled(for: context)
    }

    /// Per-action or whole-package settings disable, shared by the bar and palette.
    private func isDisabledInSettings(_ action: any Action, disabledIDs: Set<String>, disabledPackages: Set<String>) -> Bool {
        if disabledIDs.contains(action.id) { return true }
        if let packageID = ActionIdentity.extensionPackageID(of: action), disabledPackages.contains(packageID) {
            return true
        }
        return false
    }

    /// A disabled group hides its sub-actions on both surfaces. `isRowVisible` decides whether the group row survives.
    private func hiddenGroupIDs(isRowVisible: (any Action) -> Bool) -> Set<String> {
        Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions || $0.chrome.launchesAI }
                .filter { !isRowVisible($0) }
                .map(\.id)
        )
    }

    /// True when the action belongs to a group in `hiddenGroupIDs`, by id prefix or explicit membership.
    private func belongsToHiddenGroup(_ action: any Action, hiddenGroupIDs: Set<String>, memberToGroupID: [String: String]) -> Bool {
        if hiddenGroupIDs.contains(where: { action.id.hasPrefix($0 + ".") }) { return true }
        if let owningGroupID = memberToGroupID[action.id], hiddenGroupIDs.contains(owningGroupID) {
            return true
        }
        return false
    }

    /// Explicit and provider-declared membership, including AI presets with canonical IDs.
    private func groupMembership() -> [String: String] {
        var map: [String: String] = [:]
        let resolver = SubActionResolver()
        for parent in actions {
            for child in resolver.subActions(of: parent, in: actions) {
                map[child.id] = parent.id
            }
        }
        for def in groupDefs {
            for memberID in def.memberActionIDs {
                map[memberID] = def.id
            }
        }
        return map
    }

    public func availableActions(for context: ActionContext) -> [any Action] {
        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)
        func passes(_ action: any Action) -> Bool {
            // Group children stay in the catalog for sub-bars; PopupView removes them from the top-level bar.
            if action is GatedExtensionAction {
                return false
            }
            guard canPerform(action, in: context) else { return false }
            // Per-action and whole-package disable, before per-action visibility runs.
            return !isDisabledInSettings(action, disabledIDs: disabledIDs, disabledPackages: disabledPackages)
        }

        // A disabled or invisible group row hides its sub-actions, so they never leak into the bar.
        let hiddenGroups = hiddenGroupIDs(isRowVisible: passes)
        let memberToGroupID = groupMembership()

        let available = actions.filter { action in
            guard passes(action) else { return false }
            return !belongsToHiddenGroup(action, hiddenGroupIDs: hiddenGroups, memberToGroupID: memberToGroupID)
        }

        guard settingsStore.get(.contextualActionsEnabled) else {
            return available
        }

        let disabledContextualIDs = settingsStore.get(.disabledContextualActionIDs)

        var contextualMatches: [any Action] = []
        var standardActions: [any Action] = []

        for action in available {
            if !disabledContextualIDs.contains(action.id) && action.isContextual {
                contextualMatches.append(action)
            } else {
                standardActions.append(action)
            }
        }

        return contextualMatches + standardActions
    }

    /// Flat catalog for the search palette: actions the user can run now. Settings-disabled actions and
    /// those that cannot perform in this context are dropped. Group rows stay; launchers and the completion
    /// pseudo-action never do.
    public func searchCatalog(for context: ActionContext) -> [any Action] {
        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)
        // The palette lists members, not the group row, so a disabled group must hide them here.
        let hiddenGroups = hiddenGroupIDs { row in
            !isDisabledInSettings(row, disabledIDs: disabledIDs, disabledPackages: disabledPackages)
        }
        let memberToGroupID = groupMembership()

        return actions.filter { action in
            if action.chrome.launchesAI || ActionIdentity.isCompletionPseudoAction(action) || action is GatedExtensionAction {
                return false
            }
            if isDisabledInSettings(action, disabledIDs: disabledIDs, disabledPackages: disabledPackages) {
                return false
            }
            if belongsToHiddenGroup(action, hiddenGroupIDs: hiddenGroups, memberToGroupID: memberToGroupID) {
                return false
            }
            return canPerform(action, in: context)
        }
    }
}
