// ActionsTabView.swift
// OpenClip
//
// The Actions preferences tab: the reorderable action list with per-action toggles,
// package headers for multi-action extension packages, and the add/install controls.
// Split out of PreferencesView.swift.
import SwiftUI
import UniformTypeIdentifiers
import Core

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// Called by the AI Tools row's gear to open the AI tab. Wired in PreferencesView to switch
    /// `selectedTab` to `.ai` (and land on the Configure sub-tab where `isAIEnabled` lives).
    let onOpenAI: () -> Void
    @State private var showingAddActionSheet = false
    @ObservedObject private var coordinator = ActionCoordinator.shared
    /// Single observation site for action presentation (title/icon) customizations. Rows no longer
    /// subscribe to `ActionCustomizationManager.shared` directly — they receive resolved values.
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    
    /// Row model for the grouped actions list. A multi-action extension package with a single
    /// group gets a **collapsible parent** row (the group, with its own icon, a disclosure chevron,
    /// and the uninstall/toggle/configure controls) and its sub-actions nested underneath; other
    /// multi-action packages get a package header (whole-package toggle) before their actions;
    /// single-action packages and builtins stay flat.
    private enum ListRow: Identifiable {
        case packageHeader(packageID: String, title: String, gatedReason: ExtensionGateReason?)
        case groupParent(any Action)
        case action(any Action, nestedUnder: String?)

        var id: String {
            switch self {
            case .packageHeader(let packageID, _, _): return "pkg.\(packageID)"
            case .groupParent(let action): return "group.\(action.id)"
            case .action(let action, _): return action.id
            }
        }
    }
    
    private var packageActionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for action in coordinator.actions {
            if let packageID = ActionIdentity.extensionPackageID(of: action) {
                counts[packageID, default: 0] += 1
            }
        }
        return counts
    }
    
    private var groupPackageIDs: Set<String> {
        Set(
            coordinator.actions
                .filter { $0.chrome.popupBehavior == .showSubActions }
                .compactMap { ActionIdentity.extensionPackageID(of: $0) }
        )
    }

    private func isEligibleForCustomGrouping(_ action: any Action) -> Bool {
        !ActionIdentity.isAIPreset(action) &&
        !action.chrome.launchesAI &&
        action.chrome.popupBehavior != .showSubActions &&
        !(ActionIdentity.extensionPackageID(of: action).map { groupPackageIDs.contains($0) } ?? false)
    }

    private var listRows: [ListRow] {
        // Packages whose actions are a single group + its sub-actions: the group row becomes the
        // parent (it owns the controls and shows the group's own icon) and the package header is
        // skipped, so the parent never shows a generic package glyph.
        let groupPackages = groupPackageIDs
        let groupIDs = coordinator.actions
            .filter { $0.chrome.popupBehavior == .showSubActions }
            .map(\.id)

        let customGroupMembership: [String: String] = {
            var map: [String: String] = [:]
            for def in coordinator.actionGroupDefs {
                for memberID in def.memberActionIDs {
                    map[memberID] = def.id
                }
            }
            return map
        }()

        var seenPackages: Set<String> = []
        var rows: [ListRow] = []
        for action in coordinator.actions {
            // AI presets never appear here — they're managed in the AI tab (and the palette).
            // The reorderable "AI Tools" launcher action (chrome.launchesAI) renders as a normal row.
            if ActionIdentity.isAIPreset(action) {
                continue
            }
            // Extension group rows & custom group rows: the parent row. Sub-actions nest below it.
            if action.chrome.popupBehavior == .showSubActions {
                rows.append(.groupParent(action))
                continue
            }
            if let nestedUnder = customGroupMembership[action.id] {
                rows.append(.action(action, nestedUnder: nestedUnder))
                continue
            }
            if let packageID = ActionIdentity.extensionPackageID(of: action) {
                if groupPackages.contains(packageID) {
                    // A group package: every action is shown nested under its group parent
                    // (membership is the ID-prefix convention), with the group owning the controls.
                    let nestedUnder = groupIDs.first { action.id.hasPrefix($0 + ".") }
                    rows.append(.action(action, nestedUnder: nestedUnder))
                } else {
                    if !seenPackages.contains(packageID) {
                        seenPackages.insert(packageID)
                        if packageActionCounts[packageID] ?? 0 >= 2 {
                            let title: String
                            if case .extensionPkg(let name) = action.chrome.badge {
                                title = name
                            } else {
                                title = packageID
                            }
                            let gatedReason = (action as? GatedExtensionAction)?.reason
                            rows.append(.packageHeader(packageID: packageID, title: title, gatedReason: gatedReason))
                        }
                    }
                    rows.append(.action(action, nestedUnder: nil))
                }
            } else {
                rows.append(.action(action, nestedUnder: nil))
            }
        }
        return rows
    }

    /// The rows actually rendered: nested sub-actions disappear while their group parent is
    /// collapsed (the parent's disclosure chevron toggles `collapsedGroupIDs`).
    private var visibleRows: [ListRow] {
        listRows.filter { row in
            if case .action(_, let nestedUnder) = row, let groupID = nestedUnder {
                return !collapsedGroupIDs.contains(groupID)
            }
            return true
        }
    }
    

    /// Translates indices in the visible row list (which contains inert package headers and, while
    /// a group is collapsed, omits its nested rows) back to `coordinator.actions` indices so
    /// reordering stays correct despite the inserted/omitted rows.
    private func moveRows(source: IndexSet, destination: Int) {
        if source.count == 1, let sourceRowIndex = source.first, sourceRowIndex < visibleRows.count {
            if case .action(let action, _) = visibleRows[sourceRowIndex] {
                handleRowMove(actionID: action.id, destination: destination)
                return
            }
        }

        let actionIndices: [(rowIndex: Int, actionIndex: Int)] = visibleRows.enumerated().compactMap { rowIndex, row in
            let rowAction: (any Action)?
            switch row {
            case .action(let action, _): rowAction = action
            case .groupParent(let action): rowAction = action
            case .packageHeader: rowAction = nil
            }
            guard let rowAction else { return nil }
            guard let actionIndex = coordinator.actions.firstIndex(where: { $0.id == rowAction.id }) else { return nil }
            return (rowIndex, actionIndex)
        }
        let actionIndexByRow = Dictionary(uniqueKeysWithValues: actionIndices.map { ($0.rowIndex, $0.actionIndex) })
        var actionSource = IndexSet(source.compactMap { actionIndexByRow[$0] })
        // Expand: if a group parent is being moved, include its sub-actions
        let sourceIDs = Set(actionSource.map { coordinator.actions[$0].id })
        for (index, action) in coordinator.actions.enumerated() {
            if sourceIDs.contains(where: { action.id.hasPrefix($0 + ".") }) {
                actionSource.insert(index)
            }
        }
        let customGroupMemberIDs = Set(
            sourceIDs.flatMap { groupID in
                coordinator.actionGroupDefs.first(where: { $0.id == groupID })?.memberActionIDs ?? []
            }
        )
        for (index, action) in coordinator.actions.enumerated() {
            if customGroupMemberIDs.contains(action.id) {
                actionSource.insert(index)
            }
        }
        guard !actionSource.isEmpty else { return }
        let actionDestination: Int
        if let firstAtOrAfter = actionIndices.first(where: { $0.rowIndex >= destination }) {
            actionDestination = firstAtOrAfter.actionIndex
        } else {
            actionDestination = coordinator.actions.count
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            coordinator.moveActions(from: actionSource, to: actionDestination)
        }
    }

    private func insertRow(actionID: String, destination: Int) {
        handleRowMove(actionID: actionID, destination: destination)
    }

    private func handleRowMove(actionID: String, destination: Int) {
        guard let sourceActionIndex = coordinator.actions.firstIndex(where: { $0.id == actionID }) else { return }
        let sourceGroupID = coordinator.actionGroupDefs.first(where: { $0.memberActionIDs.contains(actionID) })?.id

        let actionIndices: [(rowIndex: Int, actionIndex: Int)] = visibleRows.enumerated().compactMap { rowIndex, row in
            let rowAction: (any Action)?
            switch row {
            case .action(let action, _): rowAction = action
            case .groupParent(let action): rowAction = action
            case .packageHeader: rowAction = nil
            }
            guard let rowAction else { return nil }
            guard let actionIndex = coordinator.actions.firstIndex(where: { $0.id == rowAction.id }) else { return nil }
            return (rowIndex, actionIndex)
        }
        let actionDestination: Int
        if let firstAtOrAfter = actionIndices.first(where: { $0.rowIndex >= destination }) {
            actionDestination = firstAtOrAfter.actionIndex
        } else {
            actionDestination = coordinator.actions.count
        }

        let prevRow: ListRow? = destination > 0 && destination - 1 < visibleRows.count ? visibleRows[destination - 1] : nil
        let nextRow: ListRow? = destination < visibleRows.count ? visibleRows[destination] : nil

        let prevGroupID: String? = {
            guard let prevRow else { return nil }
            switch prevRow {
            case .action(_, let nestedUnder): return nestedUnder
            case .groupParent(let a): return a.id
            case .packageHeader: return nil
            }
        }()

        let nextGroupID: String? = {
            guard let nextRow else { return nil }
            switch nextRow {
            case .action(_, let nestedUnder): return nestedUnder
            case .groupParent: return nil
            case .packageHeader: return nil
            }
        }()

        // If dropped strictly between rows belonging to the same group, target is that group
        if let prevGroupID, let nextGroupID, prevGroupID == nextGroupID,
           coordinator.actionGroupDefs.contains(where: { $0.id == prevGroupID }) {
            let targetGroupID = prevGroupID
            if targetGroupID == sourceGroupID {
                // Internal reordering within the same group
                if let groupDef = coordinator.actionGroupDefs.first(where: { $0.id == targetGroupID }) {
                    var members = groupDef.memberActionIDs
                    if let oldIndex = members.firstIndex(of: actionID) {
                        members.remove(at: oldIndex)
                        let newIndex = visibleRows[..<destination].reduce(0) { count, r in
                            if case .action(let a, let n) = r, n == targetGroupID, a.id != actionID {
                                return count + 1
                            }
                            return count
                        }
                        members.insert(actionID, at: min(newIndex, members.count))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            coordinator.updateGroup(groupID: targetGroupID, title: groupDef.title, iconName: groupDef.iconName, memberActionIDs: members)
                        }
                    }
                }
            } else {
                // Dropped into another group
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    coordinator.addToGroup(actionID: actionID, groupID: targetGroupID)
                }
            }
            return
        }

        // Destination is outside any group.
        // If the action was previously inside a custom group, dragging it here DRAGS IT OUT!
        if let sourceGroupID {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                coordinator.removeFromGroup(actionID: actionID, groupID: sourceGroupID)
                coordinator.moveActions(from: IndexSet(integer: sourceActionIndex), to: actionDestination)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                coordinator.moveActions(from: IndexSet(integer: sourceActionIndex), to: actionDestination)
            }
        }
    }

    /// Group ids whose nested sub-actions are collapsed. Starts collapsed (populated on first appear).
    @State private var collapsedGroupIDs: Set<String> = []
    /// Whether the initial collapsed state has been seeded (all groups collapsed on first appear).
    @State private var didSeedCollapsed = false

    @State private var selectedRowIDs: Set<String> = []
    @State private var showingCreateGroupSheet = false

    /// Eligible candidate action IDs for custom grouping. Only top-level standalone actions
    /// (not AI presets, not AI launcher, not group parents, not extension sub-actions,
    /// and not existing custom group members) can be selected for a new group.
    private var candidateSelectedActionIDs: [String] {
        let customGroupMemberIDs = Set(coordinator.actionGroupDefs.flatMap(\.memberActionIDs))

        return coordinator.actions.compactMap { action in
            guard selectedRowIDs.contains(action.id) else { return nil }
            guard isEligibleForCustomGrouping(action) else { return nil }
            if customGroupMemberIDs.contains(action.id) { return nil }
            return action.id
        }
    }
    
    @ViewBuilder
    private func renderPackageHeader(packageID: String, title: String, gatedReason: ExtensionGateReason?) -> some View {
        PackageHeaderRowView(packageID: packageID, title: title, gatedReason: gatedReason, disabledPackages: $disabledPackages)
            .tag("pkg.\(packageID)")
            .moveDisabled(true)
    }

    @ViewBuilder
    private func renderGroupParent(action: any Action, rowID: String) -> some View {
        let isCustomGroup = coordinator.actionGroupDefs.contains(where: { $0.id == action.id })

        ActionRowView(
            action: action,
            presentationModel: presentationModel(for: action),
            isEnabled: enabledBinding(for: action),
            onOpenAI: onOpenAI,
            isExpanded: !collapsedGroupIDs.contains(action.id),
            onToggleExpansion: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsedGroupIDs.contains(action.id) {
                        collapsedGroupIDs.remove(action.id)
                    } else {
                        collapsedGroupIDs.insert(action.id)
                    }
                }
            },
            isDropTarget: isCustomGroup,
            onDropActionID: { droppedActionID in
                guard isCustomGroup else { return }
                guard coordinator.actions.contains(where: { $0.id == droppedActionID }) else { return }
                guard let groupDef = coordinator.actionGroupDefs.first(where: { $0.id == action.id }) else { return }
                guard !groupDef.memberActionIDs.contains(droppedActionID) else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    collapsedGroupIDs.remove(action.id)
                    coordinator.addToGroup(actionID: droppedActionID, groupID: action.id)
                }
            }
        )
        .tag(rowID)
        .contextMenu {
            if isCustomGroup {
                Button(String(localized: "Ungroup"), role: .destructive) {
                    coordinator.ungroup(groupID: action.id)
                }
            }
        }
    }

    @ViewBuilder
    private func renderActionRow(action: any Action, nestedUnder: String?, rowID: String) -> some View {
        let indented = nestedUnder != nil
        let isCustomGroupMember = nestedUnder.map { groupID in
            coordinator.actionGroupDefs.contains(where: { $0.id == groupID })
        } ?? false
        let isEligible = isEligibleForCustomGrouping(action)

        ActionRowView(
            action: action,
            presentationModel: presentationModel(for: action),
            isEnabled: enabledBinding(for: action),
            onOpenAI: onOpenAI,
            indented: indented,
            showsControls: !indented || isCustomGroupMember,
            isDraggable: isEligible
        )
        .tag(rowID)
        .contextMenu {
            if let groupID = nestedUnder, isCustomGroupMember {
                Button(String(localized: "Remove from Group"), role: .destructive) {
                    coordinator.removeFromGroup(actionID: action.id, groupID: groupID)
                }
            } else if isEligible {
                if !coordinator.actionGroupDefs.isEmpty {
                    Menu(String(localized: "Add to Group")) {
                        ForEach(coordinator.actionGroupDefs, id: \.id) { groupDef in
                            Button(groupDef.title) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    collapsedGroupIDs.remove(groupDef.id)
                                    coordinator.addToGroup(actionID: action.id, groupID: groupDef.id)
                                }
                            }
                        }
                    }
                }
                if candidateSelectedActionIDs.count >= 2 && candidateSelectedActionIDs.contains(action.id) {
                    Button(String(localized: "Create Group from Selection…")) {
                        showingCreateGroupSheet = true
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selectedRowIDs) {
                Section {
                    ForEach(visibleRows) { row in
                        switch row {
                        case .packageHeader(let packageID, let title, let gatedReason):
                            renderPackageHeader(packageID: packageID, title: title, gatedReason: gatedReason)
                        case .groupParent(let action):
                            renderGroupParent(action: action, rowID: row.id)
                        case .action(let action, let nestedUnder):
                            renderActionRow(action: action, nestedUnder: nestedUnder, rowID: row.id)
                        }
                    }
                    .onMove(perform: moveRows)
                    .onInsert(of: [UTType.text, UTType.plainText]) { destination, providers in
                        guard let provider = providers.first else { return }
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let actionID = string as? String else { return }
                            Task { @MainActor in
                                insertRow(actionID: actionID, destination: destination)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack(spacing: 12) {
                Button(action: {
                    showingAddActionSheet = true
                }, label: {
                    Label("Add Custom Action", systemImage: "plus.circle")
                })

                Button(action: {
                    showingCreateGroupSheet = true
                }, label: {
                    if candidateSelectedActionIDs.count >= 2 {
                        Label(String(localized: "Group Selected (\(candidateSelectedActionIDs.count))"), systemImage: "folder.badge.plus")
                    } else {
                        Label(String(localized: "New Group"), systemImage: "folder.badge.plus")
                    }
                })
                
                Button(action: {
                    openInstallExtensionPanel()
                }, label: {
                    Label("Install Extension…", systemImage: "square.and.arrow.down")
                })
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
        .sheet(isPresented: $showingCreateGroupSheet, onDismiss: {
            selectedRowIDs = []
        }) {
            CreateGroupSheet(memberActionIDs: candidateSelectedActionIDs)
        }
        .onAppear {
            guard !didSeedCollapsed else { return }
            didSeedCollapsed = true
            collapsedGroupIDs = Set(
                coordinator.actions
                    .filter { $0.chrome.popupBehavior == .showSubActions }
                    .map(\.id)
            )
        }
    }
    
    /// Resolves a row's title/icon from `ActionCustomizationManager` — the single observation site
    /// for customizations. Passed to rows as a value so they never subscribe to the shared manager.
    private func presentationModel(for action: any Action) -> ActionPresentationModel {
        customizationManager.presented(action, surface: .table)
    }

    /// Scoped enabled binding for a row, built from the row's single source of truth:
    /// - AI Tools launcher → `AIServiceManager.isAIEnabled` (shared with the AI tab toggle)
    /// - AI preset rows → the preset's `isEnabled`
    /// - everything else → `disabledActionIDs`
    /// Reading the singletons inside the binding — rather than via `@ObservedObject` on every row —
    /// keeps rows off the shared observation fan-out: a `Toggle` reflects its own live value without
    /// re-rendering every row when an unrelated setting changes.
    private func enabledBinding(for action: any Action) -> Binding<Bool> {
        if action.chrome.launchesAI {
            return Binding(
                get: { AIServiceManager.shared.isAIEnabled },
                set: { AIServiceManager.shared.isAIEnabled = $0 }
            )
        }
        if ActionIdentity.isAIPreset(action) {
            return Binding(
                get: { AIServiceManager.shared.preset(forActionID: action.id)?.isEnabled ?? false },
                set: { enabled in
                    guard var preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
                    preset.isEnabled = enabled
                    AIServiceManager.shared.updatePreset(preset)
                }
            )
        }
        if let gated = action as? GatedExtensionAction {
            return Binding(
                get: { false },
                set: { enabled in
                    if enabled {
                        disabledActionIDs.remove(action.id)
                        disabledPackages.remove(gated.packageID)
                        Task {
                            await ExtensionManager.shared.enablePackage(packageID: gated.packageID)
                            NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                        }
                    }
                }
            )
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action) {
            return Binding(
                get: { !disabledActionIDs.contains(action.id) && !disabledPackages.contains(packageID) },
                set: { enabled in
                    if enabled {
                        disabledActionIDs.remove(action.id)
                        if disabledPackages.contains(packageID) {
                            disabledPackages.remove(packageID)
                            Task {
                                await ExtensionManager.shared.enablePackage(packageID: packageID)
                                NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                            }
                        }
                    } else {
                        disabledActionIDs.insert(action.id)
                    }
                }
            )
        }
        return Binding(
            get: { !disabledActionIDs.contains(action.id) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.remove(action.id)
                } else {
                    disabledActionIDs.insert(action.id)
                }
            }
        )
    }

    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Extension to Install")
        panel.message = String(localized: "Choose a .openclipext folder, .zip archive, or script file")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // Treat .openclipext packages as directories so they can be read
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    await MainActor.run {
                        // Post notification so any listening view refreshes its action list
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Extension Install Failed")
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: String(localized: "OK"))
                        alert.runModal()
                    }
                }
            }
        }
    }
}

@MainActor
struct ActionRowView: View {
    let action: any Action
    /// Resolved title/icon for this row, computed once by `ActionsTab` from
    /// `ActionCustomizationManager` and passed down as a value — this row never subscribes to the
    /// shared manager, so it only re-renders when its own presentation actually changes.
    let presentationModel: ActionPresentationModel
    /// Scoped, live binding from the parent (`ActionsTab`): AI manager for AI rows,
    /// `disabledActionIDs` otherwise. No per-row `@ObservedObject` on shared singletons.
    let isEnabled: Binding<Bool>
    /// Opens the AI tab (AI Tools launcher rows); nil for rows without a nav gear.
    let onOpenAI: (() -> Void)?
    /// Nested rows (group sub-actions) are indented under their parent.
    let indented: Bool
    /// The uninstall/configure controls belong to the parent row only; nested sub-action rows
    /// hide them (their enable toggle stays).
    let showsControls: Bool
    /// When non-nil, the row is a group parent: a disclosure chevron shows the expansion state and
    /// toggles it via `onToggleExpansion`.
    let isExpanded: Bool
    let onToggleExpansion: (() -> Void)?
    let isDraggable: Bool
    let isDropTarget: Bool
    let onDropActionID: (@MainActor @Sendable (String) -> Void)?

    init(action: any Action,
         presentationModel: ActionPresentationModel,
         isEnabled: Binding<Bool>,
         onOpenAI: (() -> Void)? = nil,
         indented: Bool = false,
         showsControls: Bool = true,
         isExpanded: Bool = true,
         onToggleExpansion: (() -> Void)? = nil,
         isDraggable: Bool = false,
         isDropTarget: Bool = false,
         onDropActionID: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.action = action
        self.presentationModel = presentationModel
        self.isEnabled = isEnabled
        self.onOpenAI = onOpenAI
        self.indented = indented
        self.showsControls = showsControls
        self.isExpanded = isExpanded
        self.onToggleExpansion = onToggleExpansion
        self.isDraggable = isDraggable
        self.isDropTarget = isDropTarget
        self.onDropActionID = onDropActionID
    }

    /// AI preset rows share their toggle with the AI tab: enabling/disabling here (or there)
    /// writes the preset's `isEnabled`, the single source of truth. Never touches
    /// `disabledActionIDs`, which drives the bar via ActionRegistry.availableActions.
    private var isAI: Bool {
        ActionIdentity.isAIPreset(action)
    }

    /// The "AI Tools" bar launcher also shares its toggle with the AI tab — but with
    /// `isAIEnabled`, the single source of truth for the whole AI feature. Never touches
    /// `disabledActionIDs`.
    private var isAITools: Bool {
        action.chrome.launchesAI
    }

    @State private var showingConfigSheet = false
    @State private var isDropTargeted = false
    @State private var springLoadTask: Task<Void, Never>? = nil

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 6) {
            // Disclosure chevron column (width: 10): ensures all top-level rows align compactly.
            if let onToggleExpansion {
                Button(action: onToggleExpansion) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10, height: 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 10, height: 10)
                .accessibilityLabel(isExpanded ? String(localized: "Collapse \(presentationModel.title)") : String(localized: "Expand \(presentationModel.title)"))
            } else if !indented {
                Color.clear
                    .frame(width: 10, height: 10)
            }

            // Icon Column
            ZStack {
                ActionIconView(icon: presentationModel.icon, size: 12)
            }
            .frame(width: 22, height: 22)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
            
            // Title Column
            Text(presentationModel.title)
                .font(.system(size: 12, weight: .medium))

            if let gated = action as? GatedExtensionAction, let tooltip = gateTooltip(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer()
            
            // Right-aligned controls (Remove | Toggle | Gear). The Remove and Gear buttons belong
            // to the parent row only — nested sub-actions keep just their enable toggle.
            HStack(alignment: .center, spacing: 8) {
                // Delete / Uninstall Button (if applicable)
                if showsControls {
                    switch action.chrome.source {
                    case .custom, .extensionPkg:
                        Button(action: {
                            Task {
                                do {
                                    try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                                } catch {
                                    Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                                    let failure = NSAlert()
                                    failure.messageText = String(localized: "Remove Failed")
                                    failure.informativeText = String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                                    failure.alertStyle = .warning
                                    failure.runModal()
                                }
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                        .help(String(localized: "Remove Extension"))
                        .accessibilityLabel(String(localized: "Remove Extension"))
                    case .builtin, .ai:
                        EmptyView()
                    }
                }

                // Enable/Disable Switch
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(String(localized: "Enable \(presentationModel.title)"))
                
                // Edit / Configure Button
                if showsControls {
                    if isAITools {
                        if let onOpenAI {
                            Button(action: onOpenAI) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 20, height: 20)
                            .help(String(localized: "Open AI settings"))
                            .accessibilityLabel(String(localized: "Open AI settings"))
                        }
                    } else if !isAI {
                        Button(action: {
                            showingConfigSheet.toggle()
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                                .foregroundColor(showingConfigSheet ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                        .help(action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action"))
                        .accessibilityLabel(action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action"))
                        .popover(isPresented: $showingConfigSheet, arrowEdge: .leading) {
                            if action.chrome.rowStyle == .actionGroup {
                                EditGroupSheet(groupID: action.id)
                            } else {
                                EditActionSheet(action: action)
                            }
                        }
                    }
                } else {
                    // Reserve space matching the gear button so nested row toggles align with parent
                    Color.clear
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(.leading, indented ? 22 : 0)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDropTarget && isDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .background(
            DoubleClickHandler {
                if showsControls && !isAI && !isAITools {
                    showingConfigSheet = true
                }
            }
        )
    }

    var body: some View {
        if isDropTarget {
            rowContent
                .onDrop(of: [UTType.text, UTType.plainText], delegate: GroupFolderDropDelegate(
                    groupID: action.id,
                    isTargeted: $isDropTargeted,
                    onDropActionID: { droppedID in
                        onDropActionID?(droppedID)
                    },
                    onExpand: {
                        if !isExpanded, let onToggleExpansion {
                            springLoadTask?.cancel()
                            springLoadTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                guard !Task.isCancelled else { return }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    onToggleExpansion()
                                }
                            }
                        }
                    },
                    onCancelExpand: {
                        springLoadTask?.cancel()
                        springLoadTask = nil
                    }
                ))
        } else if isDraggable {
            rowContent
                .onDrag {
                    NSItemProvider(object: action.id as NSString)
                }
        } else {
            rowContent
        }
    }
}

private struct GroupFolderDropDelegate: DropDelegate {
    let groupID: String
    @Binding var isTargeted: Bool
    let onDropActionID: (String) -> Void
    let onExpand: () -> Void
    let onCancelExpand: () -> Void

    func dropEntered(info: DropInfo) {
        isTargeted = true
        onExpand()
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        onCancelExpand()
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text, .plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        onCancelExpand()
        guard let provider = info.itemProviders(for: [.text, .plainText]).first else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let actionID = string as? String else { return }
            Task { @MainActor in
                onDropActionID(actionID)
            }
        }
        return true
    }
}

// MARK: - Native Double-Click Helper

private struct DoubleClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickNSView {
        let view = DoubleClickNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class DoubleClickNSView: NSView {
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            }
            super.mouseDown(with: event)
        }
    }
}


@MainActor
struct PackageHeaderRowView: View {
    let packageID: String
    let title: String
    let gatedReason: ExtensionGateReason?
    @Binding var disabledPackages: Set<String>
    
    var isEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { gatedReason == nil && !disabledPackages.contains(packageID) },
            set: { enabled in
                if enabled {
                    disabledPackages.remove(packageID)
                    Task {
                        await ExtensionManager.shared.enablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } else {
                    disabledPackages.insert(packageID)
                    Task {
                        await ExtensionManager.shared.disablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                }
            }
        )
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear
                .frame(width: 10, height: 10)

            Image(systemName: "shippingbox")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            if let gatedReason, let tooltip = gateTooltip(for: gatedReason) {
                GateInfoIcon(tooltip: tooltip)
            }
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(String(localized: "Enable \(title)"))

            Color.clear
                .frame(width: 20, height: 20)
        }
        .padding(.trailing, 14)
        .padding(.vertical, 1)
    }
}

/// Red ⓘ explaining why a gated extension action/package is disabled. Native
/// `.help()` tooltips are unreliable on plain (non-interactive) views inside
/// selectable `List` cells — the table-view host often never installs tooltip
/// tracking for a bare `Image` — so this wraps the icon in a plain-style Button
/// (which gets real hover/hit-testing) and pairs the tooltip with a click-through
/// popover, guaranteeing the explanation is reachable either way.
private struct GateInfoIcon: View {
    let tooltip: String
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            Text(tooltip)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(width: 250, alignment: .leading)
        }
    }
}

private func gateTooltip(for reason: ExtensionGateReason) -> String? {
    switch reason {
    case .filesChanged:
        return String(localized: "This extension was modified externally. Toggle on to verify and re-enable.")
    case .notEnabled:
        return String(localized: "New extension found in folder. Toggle on to enable.")
    case .needsNewerApp(let required):
        return String(localized: "This extension requires OpenClip \(required) or newer.")
    case .revoked:
        return nil
    }
}
