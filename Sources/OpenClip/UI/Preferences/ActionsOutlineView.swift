// ActionsOutlineView.swift
// OpenClip
//
// Native AppKit NSOutlineView wrapper for the Customize page: tree presentation, folder drop
// highlighting, spring-loaded expansion, multi-selection, and reordering. Rows carry no controls.
//
// Drag rules: a top-level action reorders, drops onto another action or into a custom group; a
// group member can leave its group; an extension command reorders within its package only.

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
        customization: ActionCustomizationManager,
        disabledActionIDs: Set<String> = [],
        disabledPackages: Set<String> = []
    ) {
        self.id = id
        self.kind = kind
        self.children = children
        self.signature = Self.computeSignature(
            id: id,
            kind: kind,
            children: children,
            using: customization,
            disabledActionIDs: disabledActionIDs,
            disabledPackages: disabledPackages
        )
        super.init()
    }

    /// For tests and synthetic nodes with an explicit signature.
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
        using customization: ActionCustomizationManager,
        disabledActionIDs: Set<String> = [],
        disabledPackages: Set<String> = []
    ) -> String {
        var sig = id + ":"
        switch kind {
        case .customGroup(let def, let action):
            let p = customization.presented(action, surface: .table)
            let dis = disabledActionIDs.contains(def.id)
            sig += "cg:\(def.title):\(def.iconName):\(def.memberActionIDs.joined(separator: ",")):\(p.title):\(String(describing: p.icon)):dis=\(dis)"
        case .extensionGroup(let action):
            let p = customization.presented(action, surface: .table)
            let dis = disabledActionIDs.contains(action.id) || (ActionIdentity.extensionPackageID(of: action).map { disabledPackages.contains($0) } ?? false)
            sig += "eg:\(p.title):\(String(describing: p.icon)):dis=\(dis)"
        case .standaloneAction(let action):
            let p = customization.presented(action, surface: .table)
            let dis = disabledActionIDs.contains(action.id) || (ActionIdentity.extensionPackageID(of: action).map { disabledPackages.contains($0) } ?? false)
            sig += "sa:\(p.title):\(String(describing: p.icon)):dis=\(dis)"
        case .packageHeader(let pkgID, let title, let gatedReason):
            let dis = disabledPackages.contains(pkgID)
            sig += "ph:\(pkgID):\(title):\(String(describing: gatedReason)):dis=\(dis)"
        case .groupMember(let action, let parentGroupID):
            let p = customization.presented(action, surface: .table)
            let dis = disabledActionIDs.contains(action.id) || disabledActionIDs.contains(parentGroupID)
                || (ActionIdentity.extensionPackageID(of: action).map { disabledPackages.contains($0) } ?? false)
            sig += "gm:\(parentGroupID):\(p.title):\(String(describing: p.icon)):dis=\(dis)"
        case .extensionSubAction(let action, let parentGroupID):
            let p = customization.presented(action, surface: .table)
            let dis = disabledActionIDs.contains(action.id) || disabledActionIDs.contains(parentGroupID)
                || (ActionIdentity.extensionPackageID(of: action).map { disabledPackages.contains($0) } ?? false)
            // Options are part of the signature so a hot-reloaded manifest re-renders the settings cog.
            let optionsSig = action.actionOptions.map { opt in
                "\(opt.identifier):\(opt.type.rawValue):\(opt.label):\(opt.defaultValue ?? ""):\(opt.options?.joined(separator: "|") ?? "")"
            }.joined(separator: ",")
            sig += "es:\(parentGroupID):\(p.title):\(String(describing: p.icon)):\(optionsSig):dis=\(dis)"
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

// MARK: - Outline Row View (Soft Selection & Native Drop Target)

@MainActor
final class OutlineTableRowView: NSTableRowView {
    /// Set by the outline view, not tracked per row, so reused rows never keep a stale highlight.
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Rounded chip corners, matching the sidebar selection.
    private static let cornerRadius: CGFloat = 10

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    /// Hover wash, and a slightly stronger chip for the selection.
    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, !isSelected else { return }
        fillRounded(NSColor.labelColor.withAlphaComponent(isDark ? 0.06 : 0.05))
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fillRounded(NSColor.labelColor.withAlphaComponent(isDark ? 0.11 : 0.08))
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Inset hairline between rows, as in a system list.
    override func drawSeparator(in dirtyRect: NSRect) {
        guard !isHovered, !isSelected else { return }
        if let outline = enclosingScrollView?.documentView as? ActionsOutlineTableView {
            let row = outline.row(for: self)
            guard row < 0 || (outline.hoveredRowIndex != row + 1 && !outline.selectedRowIndexes.contains(row + 1)) else { return }
        }
        let inset: CGFloat = 12
        let y: CGFloat = isFlipped ? bounds.maxY - 0.5 : bounds.minY + 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX + inset, y: y))
        path.line(to: NSPoint(x: bounds.maxX - inset, y: y))
        let line = isDark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.08)
        line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func fillRounded(_ color: NSColor) {
        let rect = bounds.insetBy(dx: 4, dy: 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        color.setFill()
        if isSelected,
           let outline = enclosingScrollView?.documentView as? NSOutlineView {
            let row = outline.row(for: self)
            if row >= 0 {
                // Adjacent selected rows join: square only the shared edges.
                let joinsAbove = row > 0 && outline.selectedRowIndexes.contains(row - 1)
                let joinsBelow = outline.selectedRowIndexes.contains(row + 1)
                let squareTop = isFlipped ? joinsAbove : joinsBelow
                let squareBottom = isFlipped ? joinsBelow : joinsAbove
                if squareTop {
                    path.appendRect(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
                }
                if squareBottom {
                    path.appendRect(NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
                }
                path.windingRule = .nonZero
            }
        }
        path.fill()
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set { }
    }
}

@MainActor
private final class GroupDropHighlight: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        shape.fill()
    }
}

// MARK: - Outline Table View

@MainActor
final class ActionsOutlineTableView: NSOutlineView {
    /// Owned by the table, not the row, so recycled rows never keep someone else's hover.
    private weak var hoveredRow: OutlineTableRowView?
    private var hoverTrackingArea: NSTrackingArea?
    private var pendingRename: Task<Void, Never>?
    private var lastClickTime: TimeInterval = 0
    private var didBeginDrag = false
    private var groupDropHighlight: GroupDropHighlight?
    private var dropGroup: OutlineNode?
    private(set) var highlightedDropGroupID: String?

    func cancelPendingRename() {
        pendingRename?.cancel()
        didBeginDrag = true
    }

    func showGroupDropHighlight(_ node: OutlineNode?) {
        dropGroup = node
        highlightedDropGroupID = node?.id
        updateGroupDropHighlight()
    }

    private func updateGroupDropHighlight() {
        guard let group = dropGroup else {
            groupDropHighlight?.removeFromSuperview()
            groupDropHighlight = nil
            return
        }
        let headerRow = row(forItem: group)
        guard headerRow >= 0 else { return }
        let frame = rect(ofRow: headerRow)
        let highlight = groupDropHighlight ?? GroupDropHighlight()
        highlight.frame = frame.insetBy(dx: 4, dy: 0)
        highlight.needsDisplay = true
        if groupDropHighlight == nil { addSubview(highlight) }
        groupDropHighlight = highlight
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        showGroupDropHighlight(nil)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        showGroupDropHighlight(nil)
        super.draggingEnded(sender)
    }


    var hoveredRowIndex: Int {
        hoveredRow.map { row(for: $0) } ?? -1
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        if !frame.isEmpty {
            frame.origin.x = bounds.minX + 8 + CGFloat(level(forRow: row)) * indentationPerLevel
        }
        return frame
    }

    override func layout() {
        super.layout()
        autoresizesOutlineColumn = false
        sizeLastColumnToFit()
        updateGroupDropHighlight()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        pendingRename?.cancel()
        didBeginDrag = false
        let point = convert(event.locationInWindow, from: nil)
        let clicked = row(at: point)
        let wasSelected = selectedRowIndexes.count == 1 && selectedRow == clicked
        let isSlowClick = event.timestamp - lastClickTime > NSEvent.doubleClickInterval
        lastClickTime = event.timestamp
        let plainClick = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        let cell = clicked >= 0 ? view(atColumn: 0, row: clicked, makeIfNecessary: false) : nil
        let local = cell.map { $0.convert(event.locationInWindow, from: nil) }
        let onName = local.map { $0.x >= 30 && $0.x < (cell?.bounds.width ?? 0) - 90 } ?? false
        super.mouseDown(with: event)
        guard !didBeginDrag, wasSelected, isSlowClick, plainClick, onName, event.clickCount == 1 else { return }
        pendingRename = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, let self, self.selectedRow == clicked else { return }
            _ = (self.delegate as? ActionsOutlineCoordinator)?.renameSelectedAction()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        pendingRename?.cancel()
        super.mouseDragged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        pendingRename?.cancel()
        if (event.keyCode == 36 || event.keyCode == 76),
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           (delegate as? ActionsOutlineCoordinator)?.renameSelectedAction() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredRow(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        // Rows slide under a stationary pointer; recompute hover.
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    private func updateHover(at point: NSPoint) {
        guard window != nil else { return }
        let row = self.row(at: point)
        let view = row >= 0 ? rowView(atRow: row, makeIfNecessary: false) as? OutlineTableRowView : nil
        setHoveredRow(view)
    }

    private func setHoveredRow(_ rowView: OutlineTableRowView?) {
        guard hoveredRow !== rowView else { return }
        let previousIndex = hoveredRowIndex
        hoveredRow?.isHovered = false
        rowView?.isHovered = true
        hoveredRow = rowView
        for index in [previousIndex, hoveredRowIndex] where index > 0 {
            self.rowView(atRow: index - 1, makeIfNecessary: false)?.needsDisplay = true
        }
    }

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

/// Runs under the title bar, so the overlap is measured and applied here: AppKit only insets scroll views the window owns.
@MainActor
final class ActionsScrollView: NSScrollView {
    /// Gap between the toolbar and the first row.
    private static let topPadding: CGFloat = 14

    override func layout() {
        super.layout()
        guard let window else { return }
        let overlap = max(0, convert(bounds, to: nil).maxY - window.contentLayoutRect.maxY)
        let desiredTop = overlap + Self.topPadding
        if abs(contentInsets.top - desiredTop) > 0.5 {
            contentInsets = NSEdgeInsets(top: desiredTop, left: 0, bottom: 0, right: 0)
        }
    }
}

// MARK: - SwiftUI Representable

@MainActor
struct ActionsOutlineView: NSViewRepresentable {
    @ObservedObject var coordinator: ActionCoordinator
    @ObservedObject var customizationManager: ActionCustomizationManager
    var searchQuery: String = ""
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    @Binding var selectedRowIDs: Set<String>
    let onEditGroup: (String) -> Void
    let onCreateGroupFromSelection: () -> Void
    /// Double-click on a row: opens that row's settings page.
    let onOpenNode: (OutlineNode) -> Void

    init(
        coordinator: ActionCoordinator,
        customizationManager: ActionCustomizationManager,
        searchQuery: String = "",
        disabledActionIDs: Binding<Set<String>> = .constant([]),
        disabledPackages: Binding<Set<String>> = .constant([]),
        selectedRowIDs: Binding<Set<String>> = .constant([]),
        onEditGroup: @escaping (String) -> Void = { _ in },
        onCreateGroupFromSelection: @escaping () -> Void = { },
        onOpenNode: @escaping (OutlineNode) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.customizationManager = customizationManager
        self.searchQuery = searchQuery
        self._disabledActionIDs = disabledActionIDs
        self._disabledPackages = disabledPackages
        self._selectedRowIDs = selectedRowIDs
        self.onEditGroup = onEditGroup
        self.onCreateGroupFromSelection = onCreateGroupFromSelection
        self.onOpenNode = onOpenNode
    }

    func makeCoordinator() -> ActionsOutlineCoordinator {
        ActionsOutlineCoordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ActionsScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // Inset is measured in `layout()`; the automatic one only applies to window-owned scroll views.
        scrollView.automaticallyAdjustsContentInsets = false

        let outlineView = ActionsOutlineTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .inset
        // Grid lines are drawn by OutlineTableRowView as inset hairlines.
        outlineView.gridStyleMask = .solidHorizontalGridLineMask
        outlineView.rowHeight = 40
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.backgroundColor = .clear
        outlineView.focusRingType = .none
        outlineView.allowsMultipleSelection = true
        outlineView.indentationPerLevel = 18
        outlineView.autoresizingMask = [.width]
        // Resizing the column in every layout pass feeds width back into SwiftUI and can make the window keep changing width.
        outlineView.autoresizesOutlineColumn = true
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

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
    private var renamingActionID: String?
    private var resolvedDropTarget: OutlineNode?
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

        ActionBindingStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithParent()
            }
            .store(in: &cancellables)

        AIServiceManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithParent()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openClipExtensionsDidChange)
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
        let standaloneAIIDs = parent.coordinator.standaloneAIActionIDs

        let needle = parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matchesAction(_ action: any Action) -> Bool {
            guard !needle.isEmpty else { return true }
            let title = parent.customizationManager.presented(action, surface: .table).title.lowercased()
            if title.contains(needle) { return true }
            if let alias = ActionBindingStore.shared.alias(for: action.id)?.lowercased(), alias.contains(needle) {
                return true
            }
            return action.keywords.contains { $0.lowercased().contains(needle) }
        }

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
            if ActionIdentity.isAIPreset(action), !standaloneAIIDs.contains(action.id) { continue }

            if let def = groupDefs.first(where: { $0.id == action.id }) {
                seenCustomGroups.insert(def.id)
                let groupMatches = needle.isEmpty || def.title.lowercased().contains(needle)
                let memberNodes: [OutlineNode] = def.memberActionIDs.compactMap { memberID in
                    guard let memberAction = actions.first(where: { $0.id == memberID }) else { return nil }
                    if !needle.isEmpty && !groupMatches && !matchesAction(memberAction) { return nil }
                    return OutlineNode(
                        id: memberID,
                        kind: .groupMember(action: memberAction, parentGroupID: def.id),
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    )
                }
                if needle.isEmpty || groupMatches || !memberNodes.isEmpty {
                    newRoots.append(OutlineNode(
                        id: def.id,
                        kind: .customGroup(def, action),
                        children: memberNodes,
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    ))
                }
                continue
            }

            // Rendered under its group parent.
            if memberToCustomGroup[action.id] != nil {
                continue
            }

            if action.chrome.popupBehavior == .showSubActions {
                let groupMatches = needle.isEmpty || matchesAction(action)
                let subActionNodes: [OutlineNode] = actions.compactMap { sub in
                    guard sub.id != action.id && sub.id.hasPrefix(action.id + ".") else { return nil }
                    if !needle.isEmpty && !groupMatches && !matchesAction(sub) { return nil }
                    return OutlineNode(
                        id: sub.id,
                        kind: .extensionSubAction(action: sub, parentGroupID: action.id),
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    )
                }
                if needle.isEmpty || groupMatches || !subActionNodes.isEmpty {
                    newRoots.append(OutlineNode(
                        id: action.id,
                        kind: .extensionGroup(action),
                        children: subActionNodes,
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    ))
                }
                continue
            }

            // Sub-action of an extension group: rendered under its parent.
            if let pkgID = ActionIdentity.extensionPackageID(of: action), groupPackageIDs.contains(pkgID) {
                continue
            }

            if let pkgID = ActionIdentity.extensionPackageID(of: action) {
                let pkgActions = actions.filter { ActionIdentity.extensionPackageID(of: $0) == pkgID }
                if pkgActions.count >= 2 && !seenPackages.contains(pkgID) {
                    let anyMatches = needle.isEmpty || pkgActions.contains { matchesAction($0) }
                    if anyMatches {
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
                            customization: parent.customizationManager,
                            disabledActionIDs: parent.disabledActionIDs,
                            disabledPackages: parent.disabledPackages
                        ))
                    }
                }
            }

            if action.chrome.launchesAI {
                let aiPresets = SubActionResolver().subActions(of: action, in: actions)
                guard !aiPresets.isEmpty else { continue }
                let groupMatches = needle.isEmpty || matchesAction(action)
                let subActionNodes: [OutlineNode] = aiPresets.compactMap { preset in
                    if !needle.isEmpty && !groupMatches && !matchesAction(preset) { return nil }
                    return OutlineNode(
                        id: preset.id,
                        kind: .groupMember(action: preset, parentGroupID: action.id),
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    )
                }
                if needle.isEmpty || groupMatches || !subActionNodes.isEmpty {
                    newRoots.append(OutlineNode(
                        id: action.id,
                        kind: .extensionGroup(action),
                        children: subActionNodes,
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    ))
                }
                continue
            }

            if needle.isEmpty || matchesAction(action) {
                newRoots.append(OutlineNode(
                    id: action.id,
                    kind: .standaloneAction(action),
                    customization: parent.customizationManager,
                    disabledActionIDs: parent.disabledActionIDs,
                    disabledPackages: parent.disabledPackages
                ))
            }
        }

        // Groups whose parent action is missing from `actions`.
        for def in groupDefs where !seenCustomGroups.contains(def.id) {
            let groupMatches = needle.isEmpty || def.title.lowercased().contains(needle)
            let memberNodes: [OutlineNode] = def.memberActionIDs.compactMap { memberID in
                guard let memberAction = actions.first(where: { $0.id == memberID }) else { return nil }
                if !needle.isEmpty && !groupMatches && !matchesAction(memberAction) { return nil }
                return OutlineNode(
                    id: memberID,
                    kind: .groupMember(action: memberAction, parentGroupID: def.id),
                    customization: parent.customizationManager,
                    disabledActionIDs: parent.disabledActionIDs,
                    disabledPackages: parent.disabledPackages
                )
            }
            if let dummyAction = actions.first(where: { $0.id == def.id }) {
                if needle.isEmpty || groupMatches || !memberNodes.isEmpty {
                    newRoots.append(OutlineNode(
                        id: def.id,
                        kind: .customGroup(def, dummyAction),
                        children: memberNodes,
                        customization: parent.customizationManager,
                        disabledActionIDs: parent.disabledActionIDs,
                        disabledPackages: parent.disabledPackages
                    ))
                }
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

            // Restore expansion state, or expand all groups when filtering
            if !parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for node in rootNodes where node.isGroup {
                    outlineView.expandItem(node)
                }
            } else {
                for node in rootNodes where expandedNodeIDs.contains(node.id) {
                    outlineView.expandItem(node)
                }
            }
        }

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
                    title: title,
                    packageID: packageID,
                    gatedReason: gatedReason,
                    disabledPackages: parent.$disabledPackages,
                    disabledActionIDs: parent.$disabledActionIDs
                )
            )

        case .customGroup(_, let action), .extensionGroup(let action),
             .standaloneAction(let action), .groupMember(let action, _),
             .extensionSubAction(let action, _):
            let presentation = parent.customizationManager.presented(action, surface: .table)

            cellView.setContent(
                ActionRowView(
                    action: action,
                    presentationModel: presentation,
                    disabledActionIDs: parent.$disabledActionIDs,
                    disabledPackages: parent.$disabledPackages,
                    coordinator: parent.coordinator,
                    isRenaming: renamingActionID == action.id,
                    onRename: { [weak self] title in
                        self?.finishRenaming(action: action, title: title)
                    }
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

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        (outlineView as? ActionsOutlineTableView)?.cancelPendingRename()
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        (outlineView as? ActionsOutlineTableView)?.showGroupDropHighlight(nil)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let node = item as? OutlineNode else { return nil }
        switch node.kind {
        case .packageHeader:
            return nil
        case .extensionSubAction(let action, _):
            // Draggable to reorder within its package; `validateDrop` stops it leaving.
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
        resolvedDropTarget = item as? OutlineNode
        let operation = validateDestination(outlineView, info: info, item: item, index: index)
        let highlightedGroup: OutlineNode?
        if operation.isEmpty {
            highlightedGroup = nil
        } else if let target = resolvedDropTarget, target.isGroup {
            highlightedGroup = target
        } else if let target = resolvedDropTarget, case .groupMember(_, let groupID) = target.kind {
            highlightedGroup = rootNodes.first { $0.id == groupID }
        } else {
            highlightedGroup = nil
        }
        (outlineView as? ActionsOutlineTableView)?.showGroupDropHighlight(highlightedGroup)
        return operation
    }

    private func validateDestination(
        _ outlineView: NSOutlineView,
        info: NSDraggingInfo,
        item: Any?,
        index: Int
    ) -> NSDragOperation {
        guard parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let draggedID = info.draggingPasteboard.string(forType: actionPasteboardType) else {
            return []
        }
        let draggedIDs = draggedActionIDs(from: info)

        // The last child gap and the gap after an expanded group share a y position; the leading gutter picks the root gap.
        if let group = item as? OutlineNode, group.isGroup, index == group.children.count,
           info.draggingLocation != .zero,
           !group.children.isEmpty, outlineView.isItemExpanded(group),
           draggedIDs.contains(where: { extensionGroupID(ofSubActionWithID: $0) == nil }),
           let lastChild = group.children.last,
           let rootIndex = rootNodes.firstIndex(where: { $0.id == group.id }) {
            let lastRow = outlineView.row(forItem: lastChild)
            if lastRow >= 0 {
                let point = outlineView.convert(info.draggingLocation, from: nil)
                let childFrame = outlineView.frameOfCell(atColumn: 0, row: lastRow)
                if Self.isRootGapAfterGroup(point: point, lastRow: outlineView.rect(ofRow: lastRow),
                    childContentMinX: childFrame.minX + 30) {
                    resolvedDropTarget = nil
                    outlineView.setDropItem(nil, dropChildIndex: rootIndex + 1)
                    return .move
                }
            }
        }

        // AI presets can return to their launcher. Other actions cannot join AI Tools.
        if let targetNode = item as? OutlineNode, targetNode.action?.chrome.launchesAI == true,
           index == NSOutlineViewDropOnItemIndex || index >= 0 {
            let allPresets = draggedIDs.allSatisfy { id in
                parent.coordinator.actions.contains { $0.id == id && ActionIdentity.isAIPreset($0) }
            }
            if !draggedIDs.isEmpty && allPresets { return .move }
        }
        let extensionOwners = Set(draggedIDs.compactMap { extensionGroupID(ofSubActionWithID: $0) })
        let dragIsAllExtensionCommands = !draggedIDs.isEmpty && extensionOwners.count > 0
            && draggedIDs.allSatisfy { extensionGroupID(ofSubActionWithID: $0) != nil }

        // Case 0: extension commands stay in their package. Every dragged id must belong to the target's
        // package, or the drop is refused. A mixed drag falls through so its other members still work.
        if dragIsAllExtensionCommands {
            guard extensionOwners.count == 1,
                  let owningGroupID = extensionOwners.first,
                  let targetNode = item as? OutlineNode else { return [] }
            if case .extensionGroup(let groupAction) = targetNode.kind,
               groupAction.id == owningGroupID, index >= 0 { return .move }
            if index == NSOutlineViewDropOnItemIndex,
               let parentNode = outlineView.parent(forItem: targetNode) as? OutlineNode,
               parentNode.id == owningGroupID,
               let childIndex = parentNode.children.firstIndex(where: { $0.id == targetNode.id }) {
                resolvedDropTarget = parentNode
                outlineView.setDropItem(parentNode, dropChildIndex: childIndex)
                return .move
            }
            return []
        }

        // Case 1: custom group. Judge a multi-row selection by the members that could join.
        if let targetNode = item as? OutlineNode, case .customGroup(let def, _) = targetNode.kind {
            let candidates = draggedIDs.filter {
                def.memberActionIDs.contains($0) || couldJoinGroup($0, def: def)
            }
            guard !candidates.isEmpty else { return [] }
            if index == NSOutlineViewDropOnItemIndex || index >= 0 {
                return .move
            }
        }

        // Case 2: drop ON another action makes a group of the two.
        if let targetNode = item as? OutlineNode,
           index == NSOutlineViewDropOnItemIndex,
           draggedIDs.count == 1,
           dropOntoOutcome(draggedID: draggedID, target: targetNode) != nil {
            return .move
        }

        // Case 3: drop on an item that cannot hold it: retarget to insert between rows.
        if item != nil && index == NSOutlineViewDropOnItemIndex {
            if let targetNode = item as? OutlineNode,
               let parentItem = outlineView.parent(forItem: targetNode) as? OutlineNode {
                let isSameCustomGroup = parent.coordinator.actionGroupDefs.first(where: { $0.id == parentItem.id })?.memberActionIDs.contains(draggedID) == true
                let isSameExtensionGroup = extensionGroupID(ofSubActionWithID: draggedID) == parentItem.id
                let isSameAIGroup = parentItem.action?.chrome.launchesAI == true && draggedIDs.allSatisfy { id in
                    parentItem.children.contains { $0.id == id }
                }
                if (isSameCustomGroup || isSameExtensionGroup || isSameAIGroup),
                   let childIndex = parentItem.children.firstIndex(where: { $0.id == targetNode.id }) {
                    resolvedDropTarget = parentItem
                    outlineView.setDropItem(parentItem, dropChildIndex: childIndex)
                    return .move
                }
            }
            var topLevel = item
            while let candidate = topLevel, let parent = outlineView.parent(forItem: candidate) {
                topLevel = parent
            }
            if let node = topLevel as? OutlineNode,
               let rootIndex = rootNodes.firstIndex(where: { $0.id == node.id }),
               extensionGroupID(ofSubActionWithID: draggedID) == nil {
                resolvedDropTarget = nil
                outlineView.setDropItem(nil, dropChildIndex: rootIndex)
                return .move
            }
        }

        // Case 4: root-level reorder. Extension commands never leave their package.
        if item == nil && index >= 0,
           draggedIDs.contains(where: { extensionGroupID(ofSubActionWithID: $0) == nil }) {
            // Reset the indicator to root indentation; AppKit otherwise keeps the child insertion line.
            outlineView.setDropItem(nil, dropChildIndex: index)
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
        (outlineView as? ActionsOutlineTableView)?.showGroupDropHighlight(nil)
        guard parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let draggedID = info.draggingPasteboard.string(forType: actionPasteboardType) else {
            return false
        }

        if let targetNode = item as? OutlineNode, targetNode.action?.chrome.launchesAI == true,
           index == NSOutlineViewDropOnItemIndex || index >= 0 {
            let ids = draggedActionIDs(from: info)
            guard !ids.isEmpty, ids.allSatisfy({ id in
                parent.coordinator.actions.contains { $0.id == id && ActionIdentity.isAIPreset($0) }
            }) else { return false }
            parent.coordinator.setAIActionPlacement(actionIDs: ids, standalone: false)
            if index >= 0 {
                let previousMembers = targetNode.children.map(\.id)
                let members = Self.inserting(previousMembers, moving: ids, toChildIndex: index)
                parent.coordinator.setExtensionGroupMemberOrder(groupID: targetNode.id, memberIDs: members)
            }
            expandedNodeIDs.insert(targetNode.id)
            rebuildTree()
            outlineView.reloadData()
            if let updated = rootNodes.first(where: { $0.id == targetNode.id }) {
                outlineView.expandItem(updated)
            }
            return true
        }

        if let owningGroupID = extensionGroupID(ofSubActionWithID: draggedID),
           let targetNode = item as? OutlineNode,
           case .extensionGroup(let groupAction) = targetNode.kind,
           groupAction.id == owningGroupID,
           index >= 0 {
            let members = parent.coordinator.memberActionIDs(for: owningGroupID)
            let ids = draggedActionIDs(from: info)
            guard ids.allSatisfy({ extensionGroupID(ofSubActionWithID: $0) == owningGroupID }) else { return false }
            let reordered = Self.inserting(members, moving: ids, toChildIndex: index)
            guard reordered != members else { return false }
            parent.coordinator.setExtensionGroupMemberOrder(groupID: owningGroupID, memberIDs: reordered)
            expandedNodeIDs.insert(owningGroupID)
            rebuildTree()
            outlineView.reloadData()
            if let updated = rootNodes.first(where: { $0.id == owningGroupID }) {
                outlineView.expandItem(updated)
            }
            return true
        }

        // The gap index counts selected members, so they are removed before inserting.
        if let targetNode = item as? OutlineNode, case .customGroup(let def, _) = targetNode.kind,
           index == NSOutlineViewDropOnItemIndex || index >= 0 {
            let ids = draggedActionIDs(from: info).filter {
                def.memberActionIDs.contains($0) || couldJoinGroup($0, def: def)
            }
            guard !ids.isEmpty else { return false }
            let members = Self.inserting(def.memberActionIDs, moving: ids,
                toChildIndex: index < 0 ? def.memberActionIDs.count : index)
            for id in ids where !def.memberActionIDs.contains(id) {
                parent.coordinator.addToGroup(actionID: id, groupID: def.id)
            }
            parent.coordinator.updateGroup(groupID: def.id, title: def.title,
                iconName: def.iconName, memberActionIDs: members)
            expandedNodeIDs.insert(def.id)
            rebuildTree()
            outlineView.reloadData()
            if let updated = rootNodes.first(where: { $0.id == def.id }) { outlineView.expandItem(updated) }
            return true
        }

        // Drop ON an action: group the two, or join the target's group.
        if let targetNode = item as? OutlineNode,
           index == NSOutlineViewDropOnItemIndex,
           draggedActionIDs(from: info).count == 1,
           let outcome = dropOntoOutcome(draggedID: draggedID, target: targetNode) {
            return perform(outcome, draggedID: draggedID, in: outlineView)
        }

        // Root drop: eject each dragged action from its group and move the run together. Extension commands are filtered out.
        if item == nil && index >= 0 {
            let rawIDs = draggedActionIDs(from: info)
            let selectedParents = rootNodes.filter { rawIDs.contains($0.id) && $0.isGroup }
            let carriedChildren = Set(selectedParents.flatMap { $0.children.map(\.id) })
            let draggedIDs = rawIDs.filter {
                extensionGroupID(ofSubActionWithID: $0) == nil && !carriedChildren.contains($0)
            }
            guard !draggedIDs.isEmpty else { return false }
            let rootActionIDs = Set(rootNodes.compactMap { $0.action?.id })
            let destinationCandidates = rootNodes.dropFirst(min(index, rootNodes.count)).compactMap { node -> String? in
                if let action = node.action { return action.id }
                if case .packageHeader(let packageID, _, _) = node.kind {
                    return parent.coordinator.actions.first {
                        rootActionIDs.contains($0.id) && ActionIdentity.extensionPackageID(of: $0) == packageID
                    }?.id
                }
                return nil
            }

            parent.coordinator.setAIActionPlacement(actionIDs: draggedIDs, standalone: true)

            for id in draggedIDs {
                if let sourceGroupID = parent.coordinator.actionGroupDefs.first(where: { $0.memberActionIDs.contains(id) })?.id {
                    parent.coordinator.removeFromGroup(actionID: id, groupID: sourceGroupID)
                }
            }

            let destinationActionIndex = destinationCandidates.lazy.compactMap { candidate in
                self.parent.coordinator.actions.firstIndex { $0.id == candidate }
            }.first ?? parent.coordinator.actions.count

            // A group moves together with its members.
            var movingIDs: [String] = []
            var seen = Set<String>()
            for id in draggedIDs {
                for movingID in [id] + parent.coordinator.memberActionIDs(for: id) {
                    if seen.insert(movingID).inserted {
                        movingIDs.append(movingID)
                    }
                }
            }

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

    /// Moves `id` to an outline gap index, which counts the dragged row while it is still on screen.
    static func reordered(_ members: [String], moving id: String, toChildIndex index: Int) -> [String] {
        guard members.contains(id) else { return members }
        return inserting(members, moving: [id], toChildIndex: index)
    }

    static func inserting(_ members: [String], moving ids: [String], toChildIndex index: Int) -> [String] {
        var seen = Set<String>()
        let moving = ids.filter { seen.insert($0).inserted }
        let gap = min(max(index, 0), members.count)
        let destination = gap - members.prefix(gap).filter { seen.contains($0) }.count
        var result = members.filter { !seen.contains($0) }
        result.insert(contentsOf: moving, at: destination)
        return result
    }

    static func isRootGapAfterGroup(point: NSPoint, lastRow: NSRect, childContentMinX: CGFloat) -> Bool {
        guard point.x >= lastRow.minX, point.x <= lastRow.maxX,
              point.y >= lastRow.maxY - 4, point.y <= lastRow.maxY + 8 else { return false }
        return point.x < childContentMinX || point.y > lastRow.maxY + 2
    }

    /// Every action id in a drag, in pasteboard order (multi-row drags arrive as several items).
    private func draggedActionIDs(from info: NSDraggingInfo) -> [String] {
        let ids = (info.draggingPasteboard.pasteboardItems ?? [])
            .compactMap { $0.string(forType: actionPasteboardType) }
        if !ids.isEmpty { return ids }
        return info.draggingPasteboard.string(forType: actionPasteboardType).map { [$0] } ?? []
    }

    /// Whether a dragged id may join `def`: a groupable top-level action, not a group or extension group.
    private func couldJoinGroup(_ id: String, def: ActionGroupDef) -> Bool {
        guard id != def.id else { return false }
        guard !parent.coordinator.actionGroupDefs.contains(where: { $0.id == id }) else { return false }
        guard parent.coordinator.isEligibleForGrouping(actionID: id) else { return false }
        guard !def.memberActionIDs.contains(id) else { return false }
        if let action = parent.coordinator.actions.first(where: { $0.id == id }),
           action.chrome.popupBehavior == .showSubActions {
            return false
        }
        return true
    }

    // MARK: - Grouping by drop

    /// Outcome of dropping `draggedID` onto `target`, or nil to fall through to reordering.
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
            // Custom groups are handled earlier; extension nodes cannot take members.
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

        // Expand so the result is visible.
        expandedNodeIDs.insert(groupID)
        rebuildTree()
        outlineView.reloadData()
        if let node = rootNodes.first(where: { $0.id == groupID }) {
            outlineView.expandItem(node)
        }
        return true
    }

    /// Name for a drop-created group: the plain name, then numbered once taken.
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

    func renameSelectedAction() -> Bool {
        guard let outlineView, outlineView.selectedRowIndexes.count == 1,
              let node = outlineView.item(atRow: outlineView.selectedRow) as? OutlineNode,
              node.action != nil else { return false }
        beginRenaming(node)
        return true
    }

    private func beginRenaming(_ node: OutlineNode) {
        guard node.action != nil else { return }
        renamingActionID = node.id
        outlineView?.reloadItem(node)
    }

    @objc private func handleRenameMenuItem(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? OutlineNode else { return }
        beginRenaming(node)
    }

    private func finishRenaming(action: any Action, title: String?) {
        guard renamingActionID == action.id else { return }
        renamingActionID = nil
        if let title {
            let existing = parent.customizationManager.override(for: action.id)
            parent.customizationManager.setOverride(
                for: action.id,
                title: title,
                symbol: existing?.customIconSymbol,
                text: existing?.customIconText
            )
        }
        rebuildTree()
        outlineView?.reloadData()
    }

    func contextMenu(for node: OutlineNode) -> NSMenu {
        let menu = NSMenu()
        let selectedActions = selectedActionNodes(fallback: node).compactMap(\.action)
        if node.action != nil, selectedActions.count == 1 {
            let renameItem = NSMenuItem(title: String(localized: "Rename"), action: #selector(handleRenameMenuItem(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = node
            menu.addItem(renameItem)
        }

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
            if ActionIdentity.isAIPreset(action),
               let launcher = parent.coordinator.actions.first(where: { $0.chrome.launchesAI }) {
                let addToGroupItem = NSMenuItem(title: String(localized: "Add to Group"), action: nil, keyEquivalent: "")
                let subMenu = NSMenu()
                let groupItem = NSMenuItem(title: launcher.title, action: #selector(handleAddToGroupMenuItem(_:)), keyEquivalent: "")
                groupItem.target = self
                groupItem.representedObject = (actionIDs: selectedActions.filter { ActionIdentity.isAIPreset($0) }.map(\.id), groupID: launcher.id)
                subMenu.addItem(groupItem)
                addToGroupItem.submenu = subMenu
                menu.addItem(addToGroupItem)
            }
            if parent.coordinator.isEligibleForGrouping(actionID: action.id) {
                if !parent.coordinator.actionGroupDefs.isEmpty {
                    let addToGroupItem = NSMenuItem(title: String(localized: "Add to Group"), action: nil, keyEquivalent: "")
                    let subMenu = NSMenu()
                    for def in parent.coordinator.actionGroupDefs {
                        let groupItem = NSMenuItem(title: def.title, action: #selector(handleAddToGroupMenuItem(_:)), keyEquivalent: "")
                        groupItem.target = self
                        groupItem.representedObject = (actionIDs: selectedActions.filter { parent.coordinator.isEligibleForGrouping(actionID: $0.id) }.map(\.id), groupID: def.id)
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

        case .extensionGroup(let action) where action.chrome.launchesAI:
            let ungroupItem = NSMenuItem(title: String(localized: "Ungroup"), action: #selector(handleUngroupMenuItem(_:)), keyEquivalent: "")
            ungroupItem.target = self
            ungroupItem.representedObject = action.id
            menu.addItem(ungroupItem)

        case .extensionGroup, .extensionSubAction, .packageHeader:
            break
        }

        // Duplicate/Delete act on the whole selection; custom groups are excluded (Configure/Ungroup cover them).
        let selectedNodes = selectedActionNodes(fallback: node).filter { !$0.isCustomGroup }
        let duplicable = selectedNodes.compactMap(\.action).filter { ActionIdentity.canDuplicate($0) }
        let deletable = selectedNodes.compactMap(\.action).filter { ActionDeletion.canDelete($0) }

        if !duplicable.isEmpty || !deletable.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
        }
        if !duplicable.isEmpty {
            let duplicateItem = NSMenuItem(title: String(localized: "Duplicate"), action: #selector(handleDuplicateActionsMenuItem(_:)), keyEquivalent: "d")
            duplicateItem.target = self
            duplicateItem.representedObject = duplicable.map(\.id)
            menu.addItem(duplicateItem)
        }
        if !deletable.isEmpty {
            let deleteItem = NSMenuItem(title: String(localized: "Delete"), action: #selector(handleDeleteActionsMenuItem(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = deletable.map(\.id)
            menu.addItem(deleteItem)
        }

        return menu
    }

    /// Selected rows, or just `node` when nothing is selected.
    private func selectedActionNodes(fallback node: OutlineNode) -> [OutlineNode] {
        guard let outlineView else { return [node] }
        let nodes = outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? OutlineNode }
        return nodes.isEmpty ? [node] : nodes
    }

    @objc private func handleDuplicateActionsMenuItem(_ sender: NSMenuItem) {
        guard let actionIDs = sender.representedObject as? [String] else { return }
        Task { @MainActor in
            for id in actionIDs {
                _ = await ActionDuplicator.duplicate(actionID: id)
            }
        }
    }

    @objc private func handleDeleteActionsMenuItem(_ sender: NSMenuItem) {
        guard let actionIDs = sender.representedObject as? [String], !actionIDs.isEmpty else { return }
        SettingsRouter.shared.confirmDestructive(
            title: String(localized: "Delete?"),
            message: "",
            confirmTitle: String(localized: "Delete")
        ) {
            Task { @MainActor in
                for id in actionIDs {
                    await ActionDeletion.delete(actionID: id)
                }
            }
        }
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
        if let tuple = sender.representedObject as? (actionIDs: [String], groupID: String) {
            for actionID in tuple.actionIDs {
                parent.coordinator.addToGroup(actionID: actionID, groupID: tuple.groupID)
            }
            expandedNodeIDs.insert(tuple.groupID)
            rebuildTree()
            outlineView?.reloadData()
        }
    }

    @objc private func handleCreateGroupFromSelectionMenuItem() {
        parent.onCreateGroupFromSelection()
    }
}
