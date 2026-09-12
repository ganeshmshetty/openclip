// ActionsOutlineView.swift
// OpenClip
//
// Native AppKit NSOutlineView wrapper for the Customize page.
// Implements hierarchical tree presentation, native macOS folder drop highlighting,
// spring-loaded folder expansion, multi-selection, and reordering. Rows carry no controls: the
// page is the popup bar's layout, and an action's settings are a page of their own.
//
// What can be dragged where: a top-level action reorders, drops onto another action to group the
// two, or drops into a custom group; a custom group's member can leave it; and a command of an
// extension can be reordered among its siblings but not taken out of its package.

import AppKit
import SwiftUI
import Core
import UniformTypeIdentifiers
import Combine

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
    let children: [OutlineNode]
    let signature: String

    init(
        id: String,
        kind: Kind,
        children: [OutlineNode] = [],
        customization: ActionCustomizationManager
    ) {
        self.id = id
        self.kind = kind
        self.children = children
        self.signature = Self.computeSignature(id: id, kind: kind, children: children, using: customization)
        super.init()
    }

    /// Convenience initializer for tests or synthetic nodes where a custom signature is provided directly.
    init(id: String, kind: Kind, children: [OutlineNode] = [], signature: String = "") {
        self.id = id
        self.kind = kind
        self.children = children
        self.signature = signature.isEmpty ? id : signature
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

    private static func computeSignature(
        id: String,
        kind: Kind,
        children: [OutlineNode],
        using customization: ActionCustomizationManager
    ) -> String {
        var sig = id + ":"
        switch kind {
        case .customGroup(let def, let action):
            let p = customization.presented(action, surface: .table)
            sig += "cg:\(def.title):\(def.iconName):\(def.memberActionIDs.joined(separator: ",")):\(p.title):\(String(describing: p.icon))"
        case .extensionGroup(let action):
            let p = customization.presented(action, surface: .table)
            sig += "eg:\(p.title):\(String(describing: p.icon))"
        case .standaloneAction(let action):
            let p = customization.presented(action, surface: .table)
            sig += "sa:\(p.title):\(String(describing: p.icon))"
        case .packageHeader(let pkgID, let title, let gatedReason):
            sig += "ph:\(pkgID):\(title):\(String(describing: gatedReason))"
        case .groupMember(let action, let parentGroupID):
            let p = customization.presented(action, surface: .table)
            sig += "gm:\(parentGroupID):\(p.title):\(String(describing: p.icon))"
        case .extensionSubAction(let action, let parentGroupID):
            let p = customization.presented(action, surface: .table)
            // Option schema is part of the identity so a hot-reloaded manifest that adds, drops,
            // or modifies options re-renders the row's settings cog even when title and icon are unchanged.
            let optionsSig = action.actionOptions.map { opt in
                "\(opt.identifier):\(opt.type.rawValue):\(opt.label):\(opt.defaultValue ?? ""):\(opt.options?.joined(separator: "|") ?? "")"
            }.joined(separator: ",")
            sig += "es:\(parentGroupID):\(p.title):\(String(describing: p.icon)):\(optionsSig)"
        }
        if !children.isEmpty {
            sig += "[" + children.map(\.signature).joined(separator: ";") + "]"
        }
        return sig
    }

    static func treesEqual(_ a: [OutlineNode], _ b: [OutlineNode]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if a[i].signature != b[i].signature {
                return false
            }
        }
        return true
    }

    static func treesEqual(_ a: [OutlineNode], _ b: [OutlineNode], using customization: ActionCustomizationManager) -> Bool {
        treesEqual(a, b)
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

// MARK: - Scroll View

/// Keeps the list's rows clear of the title bar while the scroll view itself runs
/// underneath it. The pane hands this view the whole detail column, title bar
/// included, so scrolled rows fade out beneath the toolbar the way every Form-based
/// pane's do; AppKit only insets scroll views the window owns directly, so the
/// overlap is measured and applied here.
@MainActor
final class ActionsScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let window else { return }
        let overlap = max(0, convert(bounds, to: nil).maxY - window.contentLayoutRect.maxY)
        guard abs(contentInsets.top - overlap) > 0.5 else { return }
        contentInsets = NSEdgeInsets(top: overlap, left: 0, bottom: 0, right: 0)
    }
}

// MARK: - SwiftUI Representable

@MainActor
struct ActionsOutlineView: NSViewRepresentable {
    @ObservedObject var coordinator: ActionCoordinator
    @ObservedObject var customizationManager: ActionCustomizationManager
    @Binding var selectedRowIDs: Set<String>
    let onEditGroup: (String) -> Void
    let onCreateGroupFromSelection: () -> Void
    /// Double-click on a row: opens that row's settings page.
    let onOpenNode: (OutlineNode) -> Void

    func makeCoordinator() -> ActionsOutlineCoordinator {
        ActionsOutlineCoordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ActionsScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // The inset is measured against the title bar in `layout()`; the automatic
        // one only fires for a scroll view the window itself owns.
        scrollView.automaticallyAdjustsContentInsets = false

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
        _ = context.coordinator.rebuildTree()
        outlineView.reloadData()

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
    var parent: ActionsOutlineView {
        didSet {
            setupSubscriptions()
        }
    }
    weak var outlineView: ActionsOutlineTableView?
    private(set) var rootNodes: [OutlineNode] = []
    private var expandedNodeIDs: Set<String> = []
    private var isSyncingSelection = false
    private var cancellables = Set<AnyCancellable>()

    init(_ parent: ActionsOutlineView) {
        self.parent = parent
        super.init()
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        cancellables.removeAll()

        parent.customizationManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithParent()
            }
            .store(in: &cancellables)

        parent.coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithParent()
            }
            .store(in: &cancellables)

        CustomIconManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithParent()
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func rebuildTree() -> Bool {
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
                    return OutlineNode(
                        id: memberID,
                        kind: .groupMember(action: memberAction, parentGroupID: def.id),
                        customization: parent.customizationManager
                    )
                }
                newRoots.append(OutlineNode(
                    id: def.id,
                    kind: .customGroup(def, action),
                    children: memberNodes,
                    customization: parent.customizationManager
                ))
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
                    return OutlineNode(
                        id: sub.id,
                        kind: .extensionSubAction(action: sub, parentGroupID: action.id),
                        customization: parent.customizationManager
                    )
                }
                newRoots.append(OutlineNode(
                    id: action.id,
                    kind: .extensionGroup(action),
                    children: subActionNodes,
                    customization: parent.customizationManager
                ))
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
                        kind: .packageHeader(packageID: pkgID, title: title, gatedReason: gatedReason),
                        customization: parent.customizationManager
                    ))
                }
            }

            // Standalone action
            newRoots.append(OutlineNode(
                id: action.id,
                kind: .standaloneAction(action),
                customization: parent.customizationManager
            ))
        }

        // Catch custom groups not yet matched in actions
        for def in groupDefs where !seenCustomGroups.contains(def.id) {
            let memberNodes: [OutlineNode] = def.memberActionIDs.compactMap { memberID in
                guard let memberAction = actions.first(where: { $0.id == memberID }) else { return nil }
                return OutlineNode(
                    id: memberID,
                    kind: .groupMember(action: memberAction, parentGroupID: def.id),
                    customization: parent.customizationManager
                )
            }
            if let dummyAction = actions.first(where: { $0.id == def.id }) {
                newRoots.append(OutlineNode(
                    id: def.id,
                    kind: .customGroup(def, dummyAction),
                    children: memberNodes,
                    customization: parent.customizationManager
                ))
            }
        }

        let changed = !OutlineNode.treesEqual(newRoots, self.rootNodes)
        if changed {
            self.rootNodes = newRoots
        }
        return changed
    }

    func syncWithParent() {
        guard let outlineView else { return }
        let changed = rebuildTree()
        if changed {
            outlineView.reloadData()

            // Restore expansion state
            for node in rootNodes where expandedNodeIDs.contains(node.id) {
                outlineView.expandItem(node)
            }
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
        case .packageHeader(_, let title, let gatedReason):
            cellView.setContent(
                PackageHeaderRowView(title: title, gatedReason: gatedReason)
            )

        case .customGroup(_, let action), .extensionGroup(let action),
             .standaloneAction(let action), .groupMember(let action, _),
             .extensionSubAction(let action, _):
            let presentation = parent.customizationManager.presented(action, surface: .table)

            cellView.setContent(
                ActionRowView(action: action, presentationModel: presentation)
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
        case .packageHeader:
            return nil
        case .extensionSubAction(let action, _):
            // Draggable so its order inside its own package can be changed; `validateDrop` is
            // what keeps it from leaving.
            let pbItem = NSPasteboardItem()
            pbItem.setString(action.id, forType: actionPasteboardType)
            return pbItem
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

        // Case 0: A command of an extension belongs to its package — it can be reordered among
        // its siblings and moved nowhere else, so every other drop is refused outright rather
        // than falling through to the retarget and root-level cases below.
        if let owningGroupID = extensionGroupID(ofSubActionWithID: draggedID) {
            guard let targetNode = item as? OutlineNode,
                  case .extensionGroup(let groupAction) = targetNode.kind,
                  groupAction.id == owningGroupID,
                  index >= 0 else { return [] }
            return .move
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

        // Case 2: Hovering ON another action -> the drop makes a group of the two, the way
        // dragging one icon onto another does on the Home screen. AppKit draws the row highlight
        // for a drop-on-item, so the affordance is already there.
        if let targetNode = item as? OutlineNode,
           index == NSOutlineViewDropOnItemIndex,
           dropOntoOutcome(draggedID: draggedID, target: targetNode) != nil {
            return .move
        }

        // Case 3: Hovering ON an item that can hold nothing -> retarget to insert between rows!
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

        // Case 4: Hovering at root level (reordering top-level actions)
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

        // Reordered inside its own extension group
        if let owningGroupID = extensionGroupID(ofSubActionWithID: draggedID),
           let targetNode = item as? OutlineNode,
           case .extensionGroup(let groupAction) = targetNode.kind,
           groupAction.id == owningGroupID,
           index >= 0 {
            let members = parent.coordinator.memberActionIDs(for: owningGroupID)
            let reordered = Self.reordered(members, moving: draggedID, toChildIndex: index)
            guard reordered != members else { return false }
            parent.coordinator.setExtensionGroupMemberOrder(groupID: owningGroupID, memberIDs: reordered)
            expandedNodeIDs.insert(owningGroupID)
            rebuildTree()
            outlineView.reloadData()
            outlineView.expandItem(targetNode)
            return true
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

        // Dropped ON another action: group the two, or join the group the target is already in.
        if let targetNode = item as? OutlineNode,
           index == NSOutlineViewDropOnItemIndex,
           let outcome = dropOntoOutcome(draggedID: draggedID, target: targetNode) {
            return perform(outcome, draggedID: draggedID, in: outlineView)
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

            // Move all actions belonging to the dragged root node (header + members/subactions)
            let movingIDs = [draggedID] + parent.coordinator.memberActionIDs(for: draggedID)

            var sourceIndices = IndexSet()
            for id in movingIDs {
                if let idx = parent.coordinator.actions.firstIndex(where: { $0.id == id }) {
                    sourceIndices.insert(idx)
                }
            }

            if !sourceIndices.isEmpty {
                parent.coordinator.moveActions(from: sourceIndices, to: destinationActionIndex)
            }
            rebuildTree()
            outlineView.reloadData()
            return true
        }

        return false
    }

    // MARK: - Reordering inside an extension's group

    /// The extension group a dragged id is a command of, or nil when it is not one.
    private func extensionGroupID(ofSubActionWithID id: String) -> String? {
        for root in rootNodes {
            for child in root.children {
                if case .extensionSubAction(let action, let parentGroupID) = child.kind, action.id == id {
                    return parentGroupID
                }
            }
        }
        return nil
    }

    /// Moves `id` to the gap an outline view reports for a drop between children.
    ///
    /// That index counts the rows *as they are on screen*, with the dragged row still among them,
    /// so moving a row downwards lands one place too far once it has been lifted out. Pure, so the
    /// off-by-one is pinned by tests rather than argued about.
    static func reordered(_ members: [String], moving id: String, toChildIndex index: Int) -> [String] {
        guard let from = members.firstIndex(of: id) else { return members }
        var reordered = members
        reordered.remove(at: from)
        let destination = index > from ? index - 1 : index
        reordered.insert(id, at: min(max(destination, 0), reordered.count))
        return reordered
    }

    // MARK: - Grouping by drop

    /// What dropping `draggedID` *onto* `target` should do, or nil when the target cannot hold it
    /// and the drop should fall through to reordering.
    enum DropOntoOutcome: Equatable {
        /// Neither action is in a group: make one holding both, the target first.
        case makeGroup(withTargetID: String)
        /// The target is already in a custom group: put the dragged action in beside it.
        case joinGroup(id: String, afterMemberID: String)
    }

    func dropOntoOutcome(draggedID: String, target: OutlineNode) -> DropOntoOutcome? {
        guard draggedID != target.id,
              parent.coordinator.isEligibleForGrouping(actionID: draggedID) else { return nil }

        switch target.kind {
        case .standaloneAction(let action):
            guard parent.coordinator.isEligibleForGrouping(actionID: action.id) else { return nil }
            return .makeGroup(withTargetID: action.id)

        case .groupMember(let action, let parentGroupID):
            // Already a sibling: this is a reorder, not a grouping.
            guard let def = parent.coordinator.actionGroupDefs.first(where: { $0.id == parentGroupID }),
                  !def.memberActionIDs.contains(draggedID) else { return nil }
            return .joinGroup(id: parentGroupID, afterMemberID: action.id)

        case .customGroup, .extensionGroup, .extensionSubAction, .packageHeader:
            // A custom group is handled before this; the rest belong to an extension package and
            // cannot take a member.
            return nil
        }
    }

    private func perform(
        _ outcome: DropOntoOutcome,
        draggedID: String,
        in outlineView: NSOutlineView
    ) -> Bool {
        let groupID: String?
        switch outcome {
        case .makeGroup(let targetID):
            let title = Self.uniqueGroupTitle(
                base: String(localized: "New Group"),
                numbered: { String(localized: "New Group \($0)") },
                existing: parent.coordinator.actionGroupDefs.map(\.title)
            )
            groupID = parent.coordinator.createGroup(
                title: title,
                iconName: "folder",
                memberActionIDs: [targetID, draggedID]
            )

        case .joinGroup(let id, let afterMemberID):
            let members = parent.coordinator.actionGroupDefs.first(where: { $0.id == id })?.memberActionIDs ?? []
            let insertion = members.firstIndex(of: afterMemberID).map { $0 + 1 }
            parent.coordinator.addToGroup(actionID: draggedID, groupID: id, atIndex: insertion)
            groupID = id
        }

        guard let groupID else { return false }

        // Open the group so the drop's result is visible rather than hidden behind a chevron.
        expandedNodeIDs.insert(groupID)
        rebuildTree()
        outlineView.reloadData()
        if let node = rootNodes.first(where: { $0.id == groupID }) {
            outlineView.expandItem(node)
        }
        return true
    }

    /// A name for a group made by dropping, which has no chance to ask for one: the plain name
    /// until it is taken, then the numbered form. Pure, so the numbering is pinned by tests.
    static func uniqueGroupTitle(
        base: String,
        numbered: (Int) -> String,
        existing: [String]
    ) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains(numbered(index)) {
            index += 1
        }
        return numbered(index)
    }

    // MARK: - Actions & Menus

    @objc func onDoubleClick(_ sender: Any?) {
        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        parent.onOpenNode(node)
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
}
