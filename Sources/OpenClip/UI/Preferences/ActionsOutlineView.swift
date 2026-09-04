// ActionsOutlineView.swift
// OpenClip
//
// Native AppKit NSOutlineView wrapper for the Actions preference tab.
// Implements hierarchical tree presentation, native macOS folder drop highlighting,
// spring-loaded folder expansion, multi-selection, and reordering.

import AppKit
import SwiftUI
import Core
import UniformTypeIdentifiers

private let actionPasteboardType = NSPasteboard.PasteboardType("com.openclip.action-id")

// MARK: - Tree Node

@MainActor
final class OutlineNode: NSObject {
    enum Kind {
        case customGroup(ActionGroupDef, any Action)
        case extensionGroup(any Action)
        case standaloneAction(any Action)
        case packageHeader(packageID: String, title: String, gatedReason: ExtensionGateReason?)
        case groupMember(action: any Action, parentGroupID: String)
        case extensionSubAction(action: any Action, parentGroupID: String)
    }

    let id: String
    let kind: Kind
    var children: [OutlineNode]

    init(id: String, kind: Kind, children: [OutlineNode] = []) {
        self.id = id
        self.kind = kind
        self.children = children
        super.init()
    }

    var isGroup: Bool {
        switch kind {
        case .customGroup, .extensionGroup: return true
        default: return false
        }
    }

    var isCustomGroup: Bool {
        switch kind {
        case .customGroup: return true
        default: return false
        }
    }

    var action: (any Action)? {
        switch kind {
        case .customGroup(_, let action): return action
        case .extensionGroup(let action): return action
        case .standaloneAction(let action): return action
        case .groupMember(let action, _): return action
        case .extensionSubAction(let action, _): return action
        case .packageHeader: return nil
        }
    }

    var groupDef: ActionGroupDef? {
        switch kind {
        case .customGroup(let def, _): return def
        default: return nil
        }
    }

    override var hash: Int { id.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? OutlineNode else { return false }
        return id == other.id
    }
}

// MARK: - Outline Cell View

private final class OutlineCellView: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    func setContent<V: View>(_ view: V) {
        let anyView = AnyView(view)
        if let hostingView {
            hostingView.rootView = anyView
        } else {
            let host = NSHostingView(rootView: anyView)
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.hostingView = host
        }
    }
}

// MARK: - Outline Row View (Soft Selection, Zebra Tinting & Native Drop Target)

@MainActor
final class OutlineTableRowView: NSTableRowView {
    var isAlternate: Bool = false

    private var currentRowIndex: Int {
        if let outline = (superview as? NSClipView)?.documentView as? NSOutlineView ?? (superview as? NSOutlineView) {
            let r = outline.row(for: self)
            if r >= 0 { return r }
        }
        return isAlternate ? 1 : 0
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSelected else { return }
        if currentRowIndex % 2 == 1 {
            let rowRect = bounds.insetBy(dx: 2, dy: 1)
            let path = NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6)
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let zebraColor = isDark
                ? NSColor.white.withAlphaComponent(0.035)
                : NSColor.black.withAlphaComponent(0.025)
            zebraColor.setFill()
            path.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let selectionRect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fillColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.09 : 0.06)
        fillColor.setFill()
        path.fill()
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override var isEmphasized: Bool {
        get { false }
        set { }
    }
}

// MARK: - Outline Table View

@MainActor
final class ActionsOutlineTableView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0, let node = item(atRow: clickedRow) as? OutlineNode else {
            return nil
        }
        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return (delegate as? ActionsOutlineCoordinator)?.contextMenu(for: node)
    }
}

// MARK: - SwiftUI Representable

@MainActor
struct ActionsOutlineView: NSViewRepresentable {
    @ObservedObject var coordinator: ActionCoordinator
    @ObservedObject var customizationManager: ActionCustomizationManager
    @Binding var selectedRowIDs: Set<String>
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    let onEditGroup: (String) -> Void
    let onCreateGroupFromSelection: () -> Void

    func makeCoordinator() -> ActionsOutlineCoordinator {
        ActionsOutlineCoordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let outlineView = ActionsOutlineTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .inset
        outlineView.rowHeight = 32
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.backgroundColor = .clear
        outlineView.focusRingType = .none
        outlineView.allowsMultipleSelection = true
        outlineView.indentationPerLevel = 18

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(ActionsOutlineCoordinator.onDoubleClick(_:))

        outlineView.registerForDraggedTypes([actionPasteboardType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        context.coordinator.outlineView = outlineView
        context.coordinator.rebuildTree()

        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncWithParent()
    }
}

// MARK: - Coordinator

@MainActor
final class ActionsOutlineCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var parent: ActionsOutlineView
    weak var outlineView: ActionsOutlineTableView?
    private(set) var rootNodes: [OutlineNode] = []
    private var expandedNodeIDs: Set<String> = []
    private var isSyncingSelection = false

    init(_ parent: ActionsOutlineView) {
        self.parent = parent
        super.init()
    }

    func rebuildTree() {
        let actions = parent.coordinator.actions
        let groupDefs = parent.coordinator.actionGroupDefs

        let groupPackageIDs = Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions }
                .compactMap { ActionIdentity.extensionPackageID(of: $0) }
        )

        var memberToCustomGroup: [String: ActionGroupDef] = [:]
        for def in groupDefs {
            for memberID in def.memberActionIDs {
                memberToCustomGroup[memberID] = def
            }
        }

        var newRoots: [OutlineNode] = []
        var seenCustomGroups = Set<String>()
        var seenPackages = Set<String>()

        for action in actions {
            if ActionIdentity.isAIPreset(action) { continue }

            // Custom Group parent
            if let def = groupDefs.first(where: { $0.id == action.id }) {
                seenCustomGroups.insert(def.id)
                let memberNodes: [OutlineNode] = def.memberActionIDs.compactMap { memberID in
                    guard let memberAction = actions.first(where: { $0.id == memberID }) else { return nil }
                    return OutlineNode(id: memberID, kind: .groupMember(action: memberAction, parentGroupID: def.id))
                }
                newRoots.append(OutlineNode(id: def.id, kind: .customGroup(def, action), children: memberNodes))
                continue
            }

            // Member of custom group (rendered under group parent)
            if memberToCustomGroup[action.id] != nil {
                continue
            }

            // Extension Group parent
            if action.chrome.popupBehavior == .showSubActions {
                let subActionNodes: [OutlineNode] = actions.compactMap { sub in
                    guard sub.id != action.id && sub.id.hasPrefix(action.id + ".") else { return nil }
                    return OutlineNode(id: sub.id, kind: .extensionSubAction(action: sub, parentGroupID: action.id))
                }
                newRoots.append(OutlineNode(id: action.id, kind: .extensionGroup(action), children: subActionNodes))
                continue
            }

            // Sub-action of extension group (rendered under extension group parent)
            if let pkgID = ActionIdentity.extensionPackageID(of: action), groupPackageIDs.contains(pkgID) {
                continue
            }

            // Non-group multi-action package header
            if let pkgID = ActionIdentity.extensionPackageID(of: action) {
                let count = actions.filter { ActionIdentity.extensionPackageID(of: $0) == pkgID }.count
                if count >= 2 && !seenPackages.contains(pkgID) {
                    seenPackages.insert(pkgID)
                    let title: String
                    if case .extensionPkg(let name) = action.chrome.badge {
                        title = name
                    } else {
                        title = pkgID
                    }
                    let gatedReason = (action as? GatedExtensionAction)?.reason
                    newRoots.append(OutlineNode(
                        id: "pkg.\(pkgID)",
                        kind: .packageHeader(packageID: pkgID, title: title, gatedReason: gatedReason)
                    ))
                }
            }

            // Standalone action
            newRoots.append(OutlineNode(id: action.id, kind: .standaloneAction(action)))
        }

        // Catch custom groups not yet matched in actions
        for def in groupDefs where !seenCustomGroups.contains(def.id) {
            let memberNodes: [OutlineNode] = def.memberActionIDs.compactMap { memberID in
                guard let memberAction = actions.first(where: { $0.id == memberID }) else { return nil }
                return OutlineNode(id: memberID, kind: .groupMember(action: memberAction, parentGroupID: def.id))
            }
            if let dummyAction = actions.first(where: { $0.id == def.id }) {
                newRoots.append(OutlineNode(id: def.id, kind: .customGroup(def, dummyAction), children: memberNodes))
            }
        }

        self.rootNodes = newRoots
    }

    func syncWithParent() {
        guard let outlineView else { return }
        rebuildTree()
        outlineView.reloadData()

        // Restore expansion state
        for node in rootNodes where expandedNodeIDs.contains(node.id) {
            outlineView.expandItem(node)
        }

        // Sync selection from parent
        guard !isSyncingSelection else { return }
        var targetIndexes = IndexSet()
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? OutlineNode, parent.selectedRowIDs.contains(node.id) {
                targetIndexes.insert(row)
            }
        }
        if outlineView.selectedRowIndexes != targetIndexes {
            outlineView.selectRowIndexes(targetIndexes, byExtendingSelection: false)
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNodes.count
        }
        if let node = item as? OutlineNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootNodes[index]
        }
        if let node = item as? OutlineNode {
            return node.children[index]
        }
        return NSObject()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? OutlineNode {
            return node.isGroup && !node.children.isEmpty
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("OutlineActionCell")
        let cellView: OutlineCellView
        if let existing = outlineView.makeView(withIdentifier: identifier, owner: self) as? OutlineCellView {
            cellView = existing
        } else {
            cellView = OutlineCellView()
            cellView.identifier = identifier
        }

        switch node.kind {
        case .packageHeader(let packageID, let title, let gatedReason):
            cellView.setContent(
                PackageHeaderRowView(
                    packageID: packageID,
                    title: title,
                    gatedReason: gatedReason,
                    disabledPackages: parent.$disabledPackages
                )
            )

        case .customGroup(_, let action), .extensionGroup(let action),
             .standaloneAction(let action), .groupMember(let action, _),
             .extensionSubAction(let action, _):
            let presentation = parent.customizationManager.presented(action, surface: .table)
            let showsControls: Bool = {
                if case .extensionSubAction = node.kind { return false }
                return true
            }()

            cellView.setContent(
                ActionRowView(
                    action: action,
                    presentationModel: presentation,
                    isEnabled: enabledBinding(for: action),
                    showsControls: showsControls
                )
            )
        }

        return cellView
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("OutlineTableRowView")
        let rowView: OutlineTableRowView
        if let existing = outlineView.makeView(withIdentifier: identifier, owner: self) as? OutlineTableRowView {
            rowView = existing
        } else {
            rowView = OutlineTableRowView()
            rowView.identifier = identifier
        }
        let rowIndex = outlineView.row(forItem: item)
        rowView.isAlternate = (rowIndex >= 0 && rowIndex % 2 == 1)
        return rowView
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? OutlineNode {
            expandedNodeIDs.insert(node.id)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? OutlineNode {
            expandedNodeIDs.remove(node.id)
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView else { return }
        isSyncingSelection = true
        var selectedIDs = Set<String>()
        for row in outlineView.selectedRowIndexes {
            if let node = outlineView.item(atRow: row) as? OutlineNode {
                selectedIDs.insert(node.id)
            }
        }
        parent.selectedRowIDs = selectedIDs
        isSyncingSelection = false
    }

    // MARK: - Drag and Drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? OutlineNode else { return nil }
        switch node.kind {
        case .packageHeader, .extensionSubAction:
            return nil
        case .standaloneAction(let action), .groupMember(let action, _):
            let pbItem = NSPasteboardItem()
            pbItem.setString(action.id, forType: actionPasteboardType)
            return pbItem
        case .customGroup, .extensionGroup:
            let pbItem = NSPasteboardItem()
            pbItem.setString(node.id, forType: actionPasteboardType)
            return pbItem
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let draggedID = info.draggingPasteboard.string(forType: actionPasteboardType) else {
            return []
        }

        // Case 1: Hovering over or inside a custom group
        if let targetNode = item as? OutlineNode, case .customGroup(let def, _) = targetNode.kind {
            // Cannot drop a group into another group
            if draggedID.hasPrefix("vgroup.") || parent.coordinator.actionGroupDefs.contains(where: { $0.id == draggedID }) {
                return []
            }
            // Cannot drop extension groups into a custom group
            if let draggedAction = parent.coordinator.actions.first(where: { $0.id == draggedID }),
               draggedAction.chrome.popupBehavior == .showSubActions {
                return []
            }
            // Ineligible actions cannot be dropped into a group
            guard parent.coordinator.isEligibleForGrouping(actionID: draggedID) else { return [] }

            if index == NSOutlineViewDropOnItemIndex {
                // Hovering ON the group folder: AppKit natively highlights the folder row!
                if def.memberActionIDs.contains(draggedID) { return [] }
                return .move
            } else if index >= 0 {
                // Hovering between members inside the group: AppKit natively renders the insertion bar!
                return .move
            }
        }

        // Case 2: Hovering ON an item that is NOT a custom group -> retarget to insert between rows!
        if item != nil && index == NSOutlineViewDropOnItemIndex {
            // Resolve the top-level ancestor of the hovered item and use its root index.
            var topLevel = item
            while let candidate = topLevel, let parent = outlineView.parent(forItem: candidate) {
                topLevel = parent
            }
            if let node = topLevel as? OutlineNode,
               let rootIndex = rootNodes.firstIndex(where: { $0.id == node.id }) {
                outlineView.setDropItem(nil, dropChildIndex: rootIndex)
                return .move
            }
        }

        // Case 3: Hovering at root level (reordering top-level actions)
        if item == nil && index >= 0 {
            return .move
        }

        return []
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let draggedID = info.draggingPasteboard.string(forType: actionPasteboardType) else {
            return false
        }

        // Dropped ON or INSIDE custom group
        if let targetNode = item as? OutlineNode, case .customGroup(let def, _) = targetNode.kind {
            if index == NSOutlineViewDropOnItemIndex {
                parent.coordinator.addToGroup(actionID: draggedID, groupID: def.id)
                expandedNodeIDs.insert(def.id)
                outlineView.expandItem(targetNode)
                rebuildTree()
                outlineView.reloadData()
                return true
            } else if index >= 0 {
                parent.coordinator.addToGroup(actionID: draggedID, groupID: def.id, atIndex: index)
                expandedNodeIDs.insert(def.id)
                outlineView.expandItem(targetNode)
                rebuildTree()
                outlineView.reloadData()
                return true
            }
        }

        // Dropped at root level
        if item == nil && index >= 0 {
            // If dragging out of a group, eject it
            if let sourceGroupID = parent.coordinator.actionGroupDefs.first(where: { $0.memberActionIDs.contains(draggedID) })?.id {
                parent.coordinator.removeFromGroup(actionID: draggedID, groupID: sourceGroupID)
            }

            let roots = self.rootNodes
            let destinationActionIndex: Int
            if index < roots.count {
                let targetNode = roots[index]
                destinationActionIndex = parent.coordinator.actions.firstIndex(where: { $0.id == targetNode.id }) ?? parent.coordinator.actions.count
            } else {
                destinationActionIndex = parent.coordinator.actions.count
            }

            if let sourceActionIndex = parent.coordinator.actions.firstIndex(where: { $0.id == draggedID }) {
                parent.coordinator.moveActions(from: IndexSet(integer: sourceActionIndex), to: destinationActionIndex)
            }
            rebuildTree()
            outlineView.reloadData()
            return true
        }

        return false
    }

    // MARK: - Actions & Menus

    @objc func onDoubleClick(_ sender: Any?) {
        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        if case .customGroup(let def, _) = node.kind {
            parent.onEditGroup(def.id)
        }
    }

    func contextMenu(for node: OutlineNode) -> NSMenu {
        let menu = NSMenu()

        switch node.kind {
        case .customGroup(let def, _):
            let editItem = NSMenuItem(title: String(localized: "Configure Group…"), action: #selector(handleEditGroupMenuItem(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = def.id
            menu.addItem(editItem)

            menu.addItem(NSMenuItem.separator())

            let ungroupItem = NSMenuItem(title: String(localized: "Ungroup"), action: #selector(handleUngroupMenuItem(_:)), keyEquivalent: "")
            ungroupItem.target = self
            ungroupItem.representedObject = def.id
            menu.addItem(ungroupItem)

        case .groupMember(let action, let parentGroupID):
            let removeItem = NSMenuItem(title: String(localized: "Remove from Group"), action: #selector(handleRemoveFromGroupMenuItem(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = (actionID: action.id, groupID: parentGroupID)
            menu.addItem(removeItem)

        case .standaloneAction(let action):
            if parent.coordinator.isEligibleForGrouping(actionID: action.id) {
                if !parent.coordinator.actionGroupDefs.isEmpty {
                    let addToGroupItem = NSMenuItem(title: String(localized: "Add to Group"), action: nil, keyEquivalent: "")
                    let subMenu = NSMenu()
                    for def in parent.coordinator.actionGroupDefs {
                        let groupItem = NSMenuItem(title: def.title, action: #selector(handleAddToGroupMenuItem(_:)), keyEquivalent: "")
                        groupItem.target = self
                        groupItem.representedObject = (actionID: action.id, groupID: def.id)
                        subMenu.addItem(groupItem)
                    }
                    addToGroupItem.submenu = subMenu
                    menu.addItem(addToGroupItem)
                }

                if parent.selectedRowIDs.count >= 2 && parent.selectedRowIDs.contains(action.id) {
                    let groupSelected = NSMenuItem(title: String(localized: "Create Group from Selection…"), action: #selector(handleCreateGroupFromSelectionMenuItem), keyEquivalent: "")
                    groupSelected.target = self
                    menu.addItem(groupSelected)
                }
            }

        case .extensionGroup, .extensionSubAction, .packageHeader:
            break
        }

        return menu
    }

    @objc private func handleEditGroupMenuItem(_ sender: NSMenuItem) {
        if let groupID = sender.representedObject as? String {
            parent.onEditGroup(groupID)
        }
    }

    @objc private func handleUngroupMenuItem(_ sender: NSMenuItem) {
        if let groupID = sender.representedObject as? String {
            parent.coordinator.ungroup(groupID: groupID)
            rebuildTree()
            outlineView?.reloadData()
        }
    }

    @objc private func handleRemoveFromGroupMenuItem(_ sender: NSMenuItem) {
        if let tuple = sender.representedObject as? (actionID: String, groupID: String) {
            parent.coordinator.removeFromGroup(actionID: tuple.actionID, groupID: tuple.groupID)
            rebuildTree()
            outlineView?.reloadData()
        }
    }

    @objc private func handleAddToGroupMenuItem(_ sender: NSMenuItem) {
        if let tuple = sender.representedObject as? (actionID: String, groupID: String) {
            parent.coordinator.addToGroup(actionID: tuple.actionID, groupID: tuple.groupID)
            expandedNodeIDs.insert(tuple.groupID)
            rebuildTree()
            outlineView?.reloadData()
        }
    }

    @objc private func handleCreateGroupFromSelectionMenuItem() {
        parent.onCreateGroupFromSelection()
    }

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
                        self.parent.disabledActionIDs.remove(action.id)
                        self.parent.disabledPackages.remove(gated.packageID)
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
                get: { !self.parent.disabledActionIDs.contains(action.id) && !self.parent.disabledPackages.contains(packageID) },
                set: { enabled in
                    if enabled {
                        self.parent.disabledActionIDs.remove(action.id)
                        if self.parent.disabledPackages.contains(packageID) {
                            self.parent.disabledPackages.remove(packageID)
                            Task {
                                await ExtensionManager.shared.enablePackage(packageID: packageID)
                                NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                            }
                        }
                    } else {
                        self.parent.disabledActionIDs.insert(action.id)
                    }
                }
            )
        }
        return Binding(
            get: { !self.parent.disabledActionIDs.contains(action.id) },
            set: { enabled in
                if enabled {
                    self.parent.disabledActionIDs.remove(action.id)
                } else {
                    self.parent.disabledActionIDs.insert(action.id)
                }
            }
        )
    }
}
