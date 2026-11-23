// ActionGroupIntegrationTests.swift
// OpenClip
//
// Integration tests covering custom action group lifecycle, extension uninstallation within groups,
// and table reordering/nesting behaviors in Preferences.
import XCTest
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class ActionGroupIntegrationTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var coordinator: ActionCoordinator!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
    }

    func testUnregisterAndReinstallExtensionInsideGroupPreservesGroupMembership() async throws {
        let extAction1 = CustomAction(id: "com.custom.ext1", title: "Ext 1", iconName: "star", type: .textSnippet(template: "1"))
        let extAction2 = CustomAction(id: "com.custom.ext2", title: "Ext 2", iconName: "star", type: .textSnippet(template: "2"))
        coordinator.register(action: extAction1)
        coordinator.register(action: extAction2)

        coordinator.createGroup(title: "My Custom Exts", iconName: "folder", memberActionIDs: ["com.custom.ext1", "com.custom.ext2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)

        // Simulating reload / reinstall unregister of canonical ID
        coordinator.unregister(actionID: "com.custom.ext1")

        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["com.custom.ext1", "com.custom.ext2"])

        // Simulating re-registration upon reinstallation
        coordinator.register(action: extAction1)

        let groupID = coordinator.actionGroupDefs[0].id
        XCTAssertEqual(coordinator.actions.first?.id, groupID)
        XCTAssertEqual(Set(coordinator.actions.dropFirst().map(\.id)), Set(["com.custom.ext1", "com.custom.ext2"]))
    }

    func testMoveCustomGroupExpandsMembersAtomically() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        let a4 = DummyAction(id: "action.4", title: "Action 4")
        coordinator.register(action: a1)
        coordinator.register(action: a2)
        coordinator.register(action: a3)
        coordinator.register(action: a4)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actions.count, 5)
        let groupID = coordinator.actionGroupDefs[0].id
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "action.1", "action.2", "action.3", "action.4"])

        // Move group (index 0, 1, 2) after action.3 (destination 4)
        let sourceIndices = IndexSet([0, 1, 2])
        coordinator.moveActions(from: sourceIndices, to: 4)

        XCTAssertEqual(coordinator.actions.map(\.id), ["action.3", groupID, "action.1", "action.2", "action.4"])
    }

    func testUngroupRestoresMembersToTopLevel() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.ungroup(groupID: groupID)
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
        XCTAssertEqual(coordinator.actions.map(\.id), ["action.1", "action.2"])
    }

    func testRemoveMemberViaCoordinatorKeepsGroupDefWithRemainingMembers() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.removeFromGroup(actionID: "action.1", groupID: groupID)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.2"])
    }

    func testDisabledGroupHidesMembersFromAvailableActions() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        settingsStore.set(.disabledActionIDs, value: [groupID])

        let context = ActionContext(
            selection: SelectionContext(
                text: "test text",
                sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )
        let available = coordinator.resolveActions(for: context)
        XCTAssertFalse(available.contains(where: { $0.id == groupID }))
        XCTAssertFalse(available.contains(where: { $0.id == "action.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "action.2" }))
    }

    func testReorderingGroupMembersUpdatesActionsOrderAndGroupDefPersistedOrder() throws {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        coordinator.register(action: a1)
        coordinator.register(action: a2)
        coordinator.register(action: a3)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let groupID = coordinator.actionGroupDefs[0].id
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "action.1", "action.2", "action.3"])

        // Move action.3 (index 3) before action.1 (destination 1)
        coordinator.moveActions(from: IndexSet(integer: 3), to: 1)

        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "action.3", "action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.3", "action.1", "action.2"])

        let persistedData = settingsStore.get(.actionGroups)
        let decoded = try ActionGroupDef.decode(from: XCTUnwrap(persistedData))
        XCTAssertEqual(decoded.first?.memberActionIDs, ["action.3", "action.1", "action.2"])
    }

    func testAddToGroupViaCoordinatorAddsActionAndUpdatesCatalogAndPersistence() throws {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        coordinator.register(action: a1)
        coordinator.register(action: a2)
        coordinator.register(action: a3)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.addToGroup(actionID: "action.3", groupID: groupID)

        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "action.1", "action.2", "action.3"])

        let persistedData = settingsStore.get(.actionGroups)
        let decoded = try ActionGroupDef.decode(from: XCTUnwrap(persistedData))
        XCTAssertEqual(decoded.first?.memberActionIDs, ["action.1", "action.2", "action.3"])
    }

    /// A group lasts exactly as long as it holds something; a removal that empties it dissolves it.
    func testAGroupLastsExactlyAsLongAsItHoldsSomething() throws {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        let emptyID = try XCTUnwrap(coordinator.createGroup(title: "Empty Group", iconName: "folder", memberActionIDs: []))
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1, "an explicitly created empty group is kept")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, [])
        XCTAssertTrue(coordinator.actions.contains { $0.id == emptyID }, "and its row is on the bar")

        // Made from two actions — which is what dropping one onto the other does — it is real.
        let groupID = try XCTUnwrap(
            coordinator.createGroup(title: "Pair", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        )
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertTrue(coordinator.actions.contains { $0.id == groupID })

        let context = ActionContext(
            selection: SelectionContext(
                text: "test text",
                sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )
        var available = coordinator.resolveActions(for: context)
        XCTAssertTrue(available.contains { $0.id == groupID }, "a group with members belongs on the bar")

        // Drag one out: the group holds the other, so it stays.
        coordinator.removeFromGroup(actionID: "action.1", groupID: groupID)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.first { $0.id == groupID }?.memberActionIDs, ["action.2"])

        // Drag the last one out: the group goes with it, and so does its row on the bar.
        coordinator.removeFromGroup(actionID: "action.2", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs.contains { $0.id == groupID })
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1, "the deliberately empty group is untouched")
        XCTAssertFalse(coordinator.actions.contains { $0.id == groupID })

        available = coordinator.resolveActions(for: context)
        XCTAssertFalse(available.contains { $0.id == groupID }, "and its row on the bar goes with it")
        XCTAssertTrue(available.contains { $0.id == "action.1" })
        XCTAssertTrue(available.contains { $0.id == "action.2" })
    }

    func testExtensionGroupMemberResolutionAndCustomization() {
        let customizationManager = ActionCustomizationManager(settingsStore: settingsStore)
        let groupAction = GroupAction(
            id: "com.pkg.leafy",
            title: "Leafy",
            icon: .symbol("leaf.fill"),
            chrome: ActionChrome(
                rowStyle: .actionGroup,
                popupBehavior: .showSubActions,
                source: .extensionPkg(packageID: "com.pkg.leafy")
            )
        )
        let subAction1 = DummyAction(
            id: "com.pkg.leafy.lookup",
            title: "Look up"
        )
        let subAction2 = DummyAction(
            id: "com.pkg.leafy.translate",
            title: "Translate"
        )
        coordinator.register(action: groupAction)
        coordinator.register(action: subAction1)
        coordinator.register(action: subAction2)

        // Member resolution returns sub-actions for extension groups
        let memberIDs = coordinator.memberActionIDs(for: groupAction.id)
        XCTAssertEqual(memberIDs, ["com.pkg.leafy.lookup", "com.pkg.leafy.translate"])

        // Customization override sets custom title and icon
        customizationManager.setOverride(for: groupAction.id, title: "My Leafy", symbol: "sparkles", text: nil)
        let presentation = customizationManager.presented(groupAction, surface: .table)
        XCTAssertEqual(presentation.title, "My Leafy")
        XCTAssertEqual(presentation.icon, .symbol("sparkles"))
    }

    /// Verifies that the outline renders cells for each supported row hierarchy.
    func testOutlineViewFrames() {
        let outlineView = ActionsOutlineTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        column.width = 380
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.style = .inset
        outlineView.indentationPerLevel = 18

        let parentView = ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: ActionCustomizationManager(settingsStore: settingsStore),
            selectedRowIDs: .constant([]),
            onEditGroup: { _ in },
            onCreateGroupFromSelection: { },
            onOpenNode: { _ in }
        )
        let coord = ActionsOutlineCoordinator(parentView)
        coord.outlineView = outlineView
        outlineView.dataSource = coord
        outlineView.delegate = coord

        let groupAction = GroupAction(
            id: "com.pkg.leafy",
            title: "Leafy",
            icon: .symbol("leaf.fill"),
            chrome: ActionChrome(
                rowStyle: .actionGroup,
                popupBehavior: .showSubActions,
                source: .extensionPkg(packageID: "com.pkg.leafy")
            )
        )
        let subAction1 = DummyAction(
            id: "com.pkg.leafy.lookup",
            title: "Look up"
        )
        coordinator.register(action: groupAction)
        coordinator.register(action: subAction1)

        let ca1 = DummyAction(id: "custom.action.1", title: "Custom Action 1", chrome: ActionChrome(rowStyle: .standard, popupBehavior: .perform, source: .custom))
        let ca2 = DummyAction(id: "custom.action.2", title: "Custom Action 2", chrome: ActionChrome(rowStyle: .standard, popupBehavior: .perform, source: .custom))
        coordinator.register(action: ca1)
        coordinator.register(action: ca2)
        coordinator.createGroup(title: "Custom Group", iconName: "folder", memberActionIDs: ["custom.action.1", "custom.action.2"])

        let ma1 = DummyAction(id: "com.pkg.multi.a1", title: "Multi Action 1", chrome: ActionChrome(rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.multi")))
        let ma2 = DummyAction(id: "com.pkg.multi.a2", title: "Multi Action 2", chrome: ActionChrome(rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.multi")))
        coordinator.register(action: ma1)
        coordinator.register(action: ma2)

        coord.rebuildTree()
        outlineView.reloadData()
        for node in coord.rootNodes {
            outlineView.expandItem(node)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.documentView = outlineView
        window.contentView = scrollView
        window.layoutIfNeeded()
        outlineView.layout()

        func findSwitches(in view: NSView) -> [NSView] {
            var results: [NSView] = []
            if NSStringFromClass(type(of: view)).contains("Switch") {
                results.append(view)
            }
            for sub in view.subviews {
                results.append(contentsOf: findSwitches(in: sub))
            }
            return results
        }

        // Each row hosts an enable switch, matching the unified customize list design.
        var renderedRows = 0
        for r in 0..<outlineView.numberOfRows {
            guard let rowView = outlineView.view(atColumn: 0, row: r, makeIfNecessary: true) else { continue }
            renderedRows += 1
            XCTAssertFalse(findSwitches(in: rowView).isEmpty, "Row \(r) should carry an enable switch")
        }
        XCTAssertGreaterThanOrEqual(renderedRows, 7, "Must render cells across every row type")
    }

    func testOutlineViewRebuildsAndReloadsOnIconCustomizationChange() {
        let customizationManager = ActionCustomizationManager(settingsStore: settingsStore)
        let parentView = ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
            selectedRowIDs: .constant([]),
            onEditGroup: { _ in },
            onCreateGroupFromSelection: { },
            onOpenNode: { _ in }
        )
        let outlineView = ActionsOutlineTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let coord = ActionsOutlineCoordinator(parentView)
        coord.outlineView = outlineView

        let action = DummyAction(id: "custom.action.icon", title: "Custom Action Icon")
        coordinator.register(action: action)

        // 1. Initial build creates the tree
        let firstBuildChanged = coord.rebuildTree()
        XCTAssertTrue(firstBuildChanged)
        XCTAssertEqual(coord.rootNodes.count, 1)

        // 2. Rebuilding without changes returns false
        let secondBuildChanged = coord.rebuildTree()
        XCTAssertFalse(secondBuildChanged)

        // 3. Modifying icon customization in ActionCustomizationManager
        customizationManager.setOverride(for: action.id, title: nil, symbol: "sparkles", text: nil)

        // 4. Rebuilding tree must detect the changed signature
        let changedAfterIconUpdate = coord.rebuildTree()
        XCTAssertTrue(changedAfterIconUpdate, "rebuildTree must detect when an action icon/override changes")

        // 5. Modifying title customization must also detect change
        customizationManager.setOverride(for: action.id, title: "New Title", symbol: "sparkles", text: nil)
        let changedAfterTitleUpdate = coord.rebuildTree()
        XCTAssertTrue(changedAfterTitleUpdate, "rebuildTree must detect when an action title/override changes")
    }

    func testOutlineViewAutoSyncsOnCustomizationPublisher() {
        let customizationManager = ActionCustomizationManager(settingsStore: settingsStore)
        let parentView = ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
            selectedRowIDs: .constant([]),
            onEditGroup: { _ in },
            onCreateGroupFromSelection: { },
            onOpenNode: { _ in }
        )
        let outlineView = ActionsOutlineTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let coord = ActionsOutlineCoordinator(parentView)
        coord.outlineView = outlineView

        let action = DummyAction(id: "custom.action.auto", title: "Auto Action")
        coordinator.register(action: action)
        coord.syncWithParent()

        let initialSignature = coord.rootNodes.first?.signature

        // Update customization; Combine listener will invoke syncWithParent on main runloop
        customizationManager.setOverride(for: action.id, title: nil, symbol: "bolt.fill", text: nil)

        // Drain main runloop to let Combine sink fire
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let updatedSignature = coord.rootNodes.first?.signature
        XCTAssertNotEqual(initialSignature, updatedSignature, "Coordinator must automatically sync when customizationManager changes")
    }

    func testSetExtensionGroupMemberOrderPersistsAndReordersInCoordinator() {
        let groupID = "com.pkg.extgroup"
        let groupAction = GroupAction(
            id: groupID,
            title: "Ext Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))
        )
        let s1 = DummyAction(id: "\(groupID).s1", title: "Sub 1")
        let s2 = DummyAction(id: "\(groupID).s2", title: "Sub 2")
        let s3 = DummyAction(id: "\(groupID).s3", title: "Sub 3")

        coordinator.register(action: groupAction)
        coordinator.register(action: s1)
        coordinator.register(action: s2)
        coordinator.register(action: s3)

        XCTAssertEqual(coordinator.memberActionIDs(for: groupID), ["\(groupID).s1", "\(groupID).s2", "\(groupID).s3"])

        coordinator.setExtensionGroupMemberOrder(groupID: groupID, memberIDs: ["\(groupID).s3", "\(groupID).s1", "\(groupID).s2"])

        XCTAssertEqual(coordinator.memberActionIDs(for: groupID), ["\(groupID).s3", "\(groupID).s1", "\(groupID).s2"])
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "\(groupID).s3", "\(groupID).s1", "\(groupID).s2"])
        XCTAssertEqual(settingsStore.get(.extensionGroupMemberOrder)[groupID], ["\(groupID).s3", "\(groupID).s1", "\(groupID).s2"])
    }

    func testMoveExtensionGroupAtomicallyPreservesSubactionsAndOrder() {
        let groupID = "com.pkg.extgroup"
        let groupAction = GroupAction(
            id: groupID,
            title: "Ext Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))
        )
        let s1 = DummyAction(id: "\(groupID).s1", title: "Sub 1")
        let s2 = DummyAction(id: "\(groupID).s2", title: "Sub 2")
        let other = DummyAction(id: "com.pkg.other", title: "Other")

        coordinator.register(action: groupAction)
        coordinator.register(action: s1)
        coordinator.register(action: s2)
        coordinator.register(action: other)

        settingsStore.set(.actionOrder, value: [groupID, "com.pkg.other"])
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "\(groupID).s1", "\(groupID).s2", "com.pkg.other"])

        // Move the group to after "com.pkg.other"
        coordinator.moveActions(from: IndexSet(integer: 0), to: 4)

        XCTAssertEqual(coordinator.actions.map(\.id), ["com.pkg.other", groupID, "\(groupID).s1", "\(groupID).s2"])
        XCTAssertEqual(settingsStore.get(.actionOrder), ["com.pkg.other", groupID])
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { _chrome }
    private let _chrome: ActionChrome

    init(
        id: String,
        title: String,
        chrome: ActionChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.leafy"))
    ) {
        self.id = id
        self.title = title
        self._chrome = chrome
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

// MARK: - Grouping by dropping one action onto another

@MainActor
final class ActionsOutlineDropTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var registry: ActionRegistry!
    private var coordinator: ActionCoordinator!
    private var outlineCoordinator: ActionsOutlineCoordinator!

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
        for index in 1...4 {
            coordinator.register(action: DummyAction(id: "action.\(index)", title: "Action \(index)"))
        }
        outlineCoordinator = ActionsOutlineCoordinator(
            ActionsOutlineView(
                coordinator: coordinator,
                customizationManager: ActionCustomizationManager(settingsStore: settingsStore),
                selectedRowIDs: .constant([]),
                onEditGroup: { _ in },
                onCreateGroupFromSelection: { },
                onOpenNode: { _ in }
            )
        )
    }

    private func action(_ id: String) -> any Action {
        coordinator.actions.first { $0.id == id }!
    }

    private func standalone(_ id: String) -> OutlineNode {
        OutlineNode(id: id, kind: .standaloneAction(action(id)))
    }

    private func registerAIPresets() {
        coordinator.register(action: AIToolsAction(settingsStore: settingsStore))
        for id in ["ai.preset.rewrite", "ai.preset.summarize"] {
            coordinator.register(action: DummyAction(id: id, title: id, chrome: ActionChrome(source: .ai)))
        }
        outlineCoordinator.rebuildTree()
    }

    func testAddToGroupMenuMovesAllSelectedActions() throws {
        let groupID = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.4"]))
        outlineCoordinator.rebuildTree()
        let outline = ActionsOutlineTableView()
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action")))
        outline.dataSource = outlineCoordinator
        outline.delegate = outlineCoordinator
        outline.allowsMultipleSelection = true
        outlineCoordinator.outlineView = outline
        outline.reloadData()
        let selectedIDs: Set<String> = ["action.1", "action.2"]
        let rows = IndexSet((0..<outline.numberOfRows).filter {
            guard let node = outline.item(atRow: $0) as? OutlineNode else { return false }
            return selectedIDs.contains(node.id)
        })
        XCTAssertEqual(rows.count, 2)
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        let menu = outlineCoordinator.contextMenu(for: standalone("action.1"))
        let add = try XCTUnwrap(menu.items.first { $0.title == "Add to Group" })
        let destination = try XCTUnwrap(add.submenu?.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(destination.action), to: destination.target, from: destination))
        XCTAssertEqual(coordinator.actionGroupDefs.first { $0.id == groupID }?.memberActionIDs, ["action.4", "action.1", "action.2"])
        XCTAssertFalse(outlineCoordinator.rootNodes.contains { selectedIDs.contains($0.id) })
    }

    func testDraggingAIPresetToRootPersistsPlacementAndOrder() throws {
        registerAIPresets()
        let id = "ai.preset.rewrite"
        let outline = NSOutlineView()
        let drag = MockDraggingInfo(actionID: id)
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0), .move)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))

        XCTAssertEqual(outlineCoordinator.rootNodes.first?.id, id)
        XCTAssertEqual(settingsStore.get(.standaloneAIActionIDs), [id])
        XCTAssertEqual(settingsStore.get(.actionOrder).first, id)
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        XCTAssertEqual(group.children.map(\.id), ["ai.preset.summarize"])

        // A fresh registry restores the same layout from the saved settings.
        let restored = ActionRegistry(settingsStore: settingsStore)
        restored.register(builtIns: Array(coordinator.actions.reversed()))
        XCTAssertEqual(restored.actions.map(\.id), coordinator.actions.map(\.id))
        let context = ActionContext(selection: SelectionContext(
            text: "Example", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default
        ))
        XCTAssertTrue(restored.availableActions(for: context).contains { $0.id == id })
        let available = restored.availableActions(for: context)
        let popup = PopupView(actions: available, context: context, onResult: { _ in })
        XCTAssertFalse(popup.displayActions.contains { $0.id == "ai.preset.summarize" })
        XCTAssertEqual(SubActionResolver().subActions(of: AIToolsAction(settingsStore: settingsStore), in: available).map(\.id), ["ai.preset.summarize"])
        settingsStore.set(.disabledActionIDs, value: [id])
        XCTAssertFalse(restored.availableActions(for: context).contains { $0.id == id })
    }

    func testDraggingAIPresetBackToToolsRemovesStandaloneOrder() throws {
        registerAIPresets()
        let id = "ai.preset.rewrite"
        let outline = NSOutlineView()
        let drag = MockDraggingInfo(actionID: id)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: NSOutlineViewDropOnItemIndex), .move)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: NSOutlineViewDropOnItemIndex))
        XCTAssertTrue(settingsStore.get(.standaloneAIActionIDs).isEmpty)
        XCTAssertFalse(settingsStore.get(.actionOrder).contains(id))
        XCTAssertFalse(outlineCoordinator.rootNodes.contains { $0.id == id })
        let updatedGroup = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == group.id })
        XCTAssertEqual(updatedGroup.children.map(\.id), [id, "ai.preset.summarize"])
    }

    func testDetachedPresetKeepsPositionWhenPresetsReloadAndLauncherMoves() throws {
        registerAIPresets()
        let id = "ai.preset.rewrite"
        let outline = NSOutlineView()
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: MockDraggingInfo(actionID: id), item: nil, childIndex: 0))
        coordinator.replaceActions(matching: { ActionIdentity.isAIPreset($0) }, with: [
            DummyAction(id: "ai.preset.summarize", title: "Summarize", chrome: ActionChrome(source: .ai)),
            DummyAction(id: id, title: "Renamed", chrome: ActionChrome(source: .ai))
        ])
        outlineCoordinator.rebuildTree()
        let rootCount = outlineCoordinator.rootNodes.count
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: MockDraggingInfo(actionID: "builtin.aiTools"), item: nil, childIndex: rootCount))
        XCTAssertEqual(outlineCoordinator.rootNodes.first?.id, id)
        XCTAssertEqual(outlineCoordinator.rootNodes.first?.action?.title, "Renamed")
        XCTAssertEqual(outlineCoordinator.rootNodes.last?.children.map(\.id), ["ai.preset.summarize"])
    }

    func testDraggingMultipleAIPresetsToRootMovesEachOnlyOnce() {
        registerAIPresets()
        let ids = ["ai.preset.rewrite", "ai.preset.summarize"]
        XCTAssertTrue(outlineCoordinator.outlineView(NSOutlineView(), acceptDrop: MockDraggingInfo(actionIDs: ids), item: nil, childIndex: 0))
        XCTAssertEqual(Array(outlineCoordinator.rootNodes.prefix(2).map(\.id)), ids)
        XCTAssertEqual(settingsStore.get(.standaloneAIActionIDs), Set(ids))
        XCTAssertFalse(outlineCoordinator.rootNodes.contains { $0.id == "builtin.aiTools" })
    }

    func testAIGroupContextMenusUngroupAndRestoreAnEmptyGroup() throws {
        registerAIPresets()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        let ungroup = try XCTUnwrap(outlineCoordinator.contextMenu(for: group).items.first { $0.title == "Ungroup" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(ungroup.action), to: ungroup.target, from: ungroup))
        XCTAssertFalse(outlineCoordinator.rootNodes.contains { $0.id == group.id })
        XCTAssertEqual(settingsStore.get(.standaloneAIActionIDs), ["ai.preset.rewrite", "ai.preset.summarize"])

        let preset = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "ai.preset.rewrite" })
        let add = try XCTUnwrap(outlineCoordinator.contextMenu(for: preset).items.first { $0.title == "Add to Group" })
        let restore = try XCTUnwrap(add.submenu?.items.first)
        XCTAssertEqual(restore.title, "AI Tools")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(restore.action), to: restore.target, from: restore))
        let restored = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == group.id })
        XCTAssertEqual(restored.children.map(\.id), [preset.id])
        XCTAssertEqual(settingsStore.get(.standaloneAIActionIDs), ["ai.preset.summarize"])
    }

    func testRemoveFromAIGroupContextMenuMovesThePresetToRoot() throws {
        registerAIPresets()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        let preset = try XCTUnwrap(group.children.first)
        let remove = try XCTUnwrap(outlineCoordinator.contextMenu(for: preset).items.first { $0.title == "Remove from Group" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(remove.action), to: remove.target, from: remove))
        XCTAssertTrue(outlineCoordinator.rootNodes.contains { $0.id == preset.id })
        XCTAssertEqual(settingsStore.get(.standaloneAIActionIDs), [preset.id])
    }

    func testReturningPresetBetweenAIGroupMembersRestoresSubBarAndOrder() throws {
        registerAIPresets()
        let outline = NSOutlineView()
        let drag = MockDraggingInfo(actionID: "ai.preset.rewrite")
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: 1), .move)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: 1))
        let restored = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == group.id })
        XCTAssertEqual(restored.children.map(\.id), ["ai.preset.summarize", "ai.preset.rewrite"])
        let context = ActionContext(selection: SelectionContext(
            text: "Example", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default
        ))
        let available = coordinator.resolveActions(for: context)
        XCTAssertEqual(SubActionResolver().subActions(of: try XCTUnwrap(restored.action), in: available).map(\.id), restored.children.map(\.id))
    }

    func testNonAIActionsCannotBePlacedInsideAITools() throws {
        registerAIPresets()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        XCTAssertFalse(outlineCoordinator.outlineView(NSOutlineView(), acceptDrop: MockDraggingInfo(actionID: "action.1"), item: group, childIndex: NSOutlineViewDropOnItemIndex))
        coordinator.setAIActionPlacement(actionIDs: ["action.1", "missing"], standalone: true)
        XCTAssertTrue(settingsStore.get(.standaloneAIActionIDs).isEmpty)
    }

    // MARK: - Reordering inside an extension's group

    private func makeDropOutline() -> ActionsOutlineTableView {
        let outline = ActionsOutlineTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action")))
        outline.dataSource = outlineCoordinator
        outline.delegate = outlineCoordinator
        outlineCoordinator.outlineView = outline
        outline.reloadData()
        for node in outlineCoordinator.rootNodes where node.isGroup { outline.expandItem(node) }
        return outline
    }

    func testMultipleGroupMembersMoveTogetherIntoReportedGap() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder",
            memberActionIDs: ["action.1", "action.2", "action.3", "action.4"]))
        outlineCoordinator.rebuildTree()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == id })
        let outline = makeDropOutline()
        let drag = MockDraggingInfo(actionIDs: ["action.1", "action.2"])
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: 4), .move)
        XCTAssertEqual(outline.highlightedDropGroupID, id)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: 4))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.3", "action.4", "action.1", "action.2"])
        XCTAssertNil(outline.highlightedDropGroupID)
    }

    func testMultipleExtensionCommandsReorderTogether() throws {
        let groupID = "com.pkg.extgroup"
        coordinator.register(action: GroupAction(id: groupID, title: "Extensions", icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))))
        let ids = (1...4).map { "\(groupID).s\($0)" }
        for id in ids { coordinator.register(action: DummyAction(id: id, title: id)) }
        outlineCoordinator.rebuildTree()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == groupID })
        let outline = makeDropOutline()
        let drag = MockDraggingInfo(actionIDs: Array(ids.prefix(2)))
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: 4), .move)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: 4))
        XCTAssertEqual(coordinator.memberActionIDs(for: groupID), [ids[2], ids[3], ids[0], ids[1]])
    }

    func testDroppingMembersOnTheirOwnGroupHeaderKeepsThemGrouped() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"]))
        outlineCoordinator.rebuildTree()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == id })
        let outline = makeDropOutline()
        let drag = MockDraggingInfo(actionID: "action.1")
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: NSOutlineViewDropOnItemIndex), .move)
        XCTAssertEqual(outline.highlightedDropGroupID, id)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: NSOutlineViewDropOnItemIndex))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.2", "action.3", "action.1"])
    }

    func testMixedExistingAndIncomingMembersKeepDropOrder() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"]))
        outlineCoordinator.rebuildTree()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == id })
        XCTAssertTrue(outlineCoordinator.outlineView(NSOutlineView(), acceptDrop: MockDraggingInfo(actionIDs: ["action.1", "action.4"]), item: group, childIndex: 3))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.2", "action.3", "action.1", "action.4"])
    }

    func testMovingLastGroupMemberOutPreservesRootDestination() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1"]))
        outlineCoordinator.rebuildTree()
        let index = try XCTUnwrap(outlineCoordinator.rootNodes.firstIndex { $0.id == id })
        let outline = makeDropOutline()
        let drag = MockDraggingInfo(actionID: "action.1")
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: index), .move)
        XCTAssertNil(outline.highlightedDropGroupID)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: index))
        XCTAssertFalse(coordinator.actionGroupDefs.contains { $0.id == id })
        XCTAssertEqual(outlineCoordinator.rootNodes.compactMap { $0.action?.id }, ["action.1", "action.2", "action.3", "action.4"])
    }

    func testDraggingGroupWithItsSelectedChildDoesNotUngroupChild() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"]))
        outlineCoordinator.rebuildTree()
        let count = outlineCoordinator.rootNodes.count
        XCTAssertTrue(outlineCoordinator.outlineView(NSOutlineView(), acceptDrop: MockDraggingInfo(actionIDs: [id, "action.1"]), item: nil, childIndex: count))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actions.map(\.id), ["action.3", "action.4", id, "action.1", "action.2"])
    }

    func testHoveringAISiblingRetainsGroupDestination() throws {
        registerAIPresets()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == "builtin.aiTools" })
        let outline = makeDropOutline()
        let drag = MockDraggingInfo(actionID: group.children[0].id)
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group.children[1], proposedChildIndex: NSOutlineViewDropOnItemIndex), .move)
        XCTAssertEqual(outline.highlightedDropGroupID, group.id)
    }

    func testLeadingBottomEdgeMovesMemberAfterItsGroup() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"]))
        outlineCoordinator.rebuildTree()
        let rootIndex = try XCTUnwrap(outlineCoordinator.rootNodes.firstIndex { $0.id == id })
        let group = outlineCoordinator.rootNodes[rootIndex]
        let outline = makeDropOutline()
        let lastRow = outline.row(forItem: try XCTUnwrap(group.children.last))
        XCTAssertGreaterThanOrEqual(lastRow, 0)
        let frame = outline.rect(ofRow: lastRow)
        let point = NSPoint(x: frame.minX + 5, y: frame.maxY - 1)
        let drag = MockDraggingInfo(actionID: "action.1")
        drag.draggingLocation = outline.convert(point, to: nil)
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: group.children.count), .move)
        XCTAssertNil(outline.highlightedDropGroupID)
        // AppKit forwards the retargeted root gap to acceptDrop.
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: rootIndex + 1))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.2"])
        let rootIDs = outlineCoordinator.rootNodes.compactMap { $0.action?.id }
        XCTAssertEqual(rootIDs, [id, "action.1", "action.3", "action.4"])
    }

    func testIndentedBottomEdgeKeepsMemberInsideGroup() throws {
        let id = try XCTUnwrap(coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"]))
        outlineCoordinator.rebuildTree()
        let group = try XCTUnwrap(outlineCoordinator.rootNodes.first { $0.id == id })
        let outline = makeDropOutline()
        let lastRow = outline.row(forItem: try XCTUnwrap(group.children.last))
        let rowFrame = outline.rect(ofRow: lastRow)
        let cellFrame = outline.frameOfCell(atColumn: 0, row: lastRow)
        let drag = MockDraggingInfo(actionID: "action.1")
        drag.draggingLocation = outline.convert(NSPoint(x: cellFrame.minX + 60, y: rowFrame.maxY - 1), to: nil)
        XCTAssertEqual(outlineCoordinator.outlineView(outline, validateDrop: drag, proposedItem: group, proposedChildIndex: group.children.count), .move)
        XCTAssertEqual(outline.highlightedDropGroupID, id)
        XCTAssertTrue(outlineCoordinator.outlineView(outline, acceptDrop: drag, item: group, childIndex: group.children.count))
        XCTAssertEqual(coordinator.memberActionIDs(for: id), ["action.2", "action.1"])
    }

    func testBottomGapHitRegionDistinguishesIndentation() {
        let row = NSRect(x: 0, y: 100, width: 600, height: 40)
        XCTAssertTrue(ActionsOutlineCoordinator.isRootGapAfterGroup(point: NSPoint(x: 10, y: 139), lastRow: row, childContentMinX: 50))
        XCTAssertFalse(ActionsOutlineCoordinator.isRootGapAfterGroup(point: NSPoint(x: 100, y: 139), lastRow: row, childContentMinX: 50))
        XCTAssertTrue(ActionsOutlineCoordinator.isRootGapAfterGroup(point: NSPoint(x: 100, y: 145), lastRow: row, childContentMinX: 50))
        XCTAssertFalse(ActionsOutlineCoordinator.isRootGapAfterGroup(point: NSPoint(x: 10, y: 120), lastRow: row, childContentMinX: 50))
    }

    func testBlockInsertionCorrectsGapAndDeduplicates() {
        XCTAssertEqual(ActionsOutlineCoordinator.inserting(["a", "b", "c", "d"], moving: ["a", "c", "a"], toChildIndex: 4), ["b", "d", "a", "c"])
        XCTAssertEqual(ActionsOutlineCoordinator.inserting(["a", "b", "c"], moving: ["c", "a"], toChildIndex: 0), ["c", "a", "b"])
        XCTAssertEqual(ActionsOutlineCoordinator.inserting(["a", "b", "c"], moving: ["a", "b"], toChildIndex: 2), ["a", "b", "c"])
    }

    func testMovingACommandDownLandsWhereTheGapWas() {
        let members = ["a", "b", "c", "d"]
        // The outline counts the gaps with the dragged row still in place, so dropping "a" into
        // the gap before "d" (index 3) must leave it *after* "c", not after "d".
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "a", toChildIndex: 3),
                       ["b", "c", "a", "d"])
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "a", toChildIndex: 4),
                       ["b", "c", "d", "a"], "the gap below the last row")
    }

    func testMovingACommandUpLandsInTheGapItself() {
        let members = ["a", "b", "c", "d"]
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "d", toChildIndex: 0),
                       ["d", "a", "b", "c"])
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "c", toChildIndex: 1),
                       ["a", "c", "b", "d"])
    }

    func testDroppingACommandBackWhereItWasChangesNothing() {
        let members = ["a", "b", "c", "d"]
        for (index, id) in members.enumerated() {
            XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: id, toChildIndex: index),
                           members, "\(id) dropped into its own gap")
            XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: id, toChildIndex: index + 1),
                           members, "\(id) dropped into the gap just below itself")
        }
    }

    func testReorderingKeepsEveryCommandAndIgnoresAStranger() {
        let members = ["a", "b", "c", "d"]
        for id in members {
            for index in 0...members.count {
                let result = ActionsOutlineCoordinator.reordered(members, moving: id, toChildIndex: index)
                XCTAssertEqual(Set(result), Set(members), "nothing lost moving \(id) to \(index)")
                XCTAssertEqual(result.count, members.count, "nothing duplicated moving \(id) to \(index)")
            }
        }
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "zzz", toChildIndex: 0), members)
        XCTAssertEqual(ActionsOutlineCoordinator.reordered(members, moving: "a", toChildIndex: 99), ["b", "c", "d", "a"])
    }

    func testDroppingAnActionOntoAnotherMakesAGroupOfTheTwo() {
        let outcome = outlineCoordinator.dropOntoOutcome(draggedID: "action.2", target: standalone("action.1"))
        XCTAssertEqual(outcome, .makeGroup(withTargetID: "action.1"),
                       "the target leads the group, the way the row you dropped onto stays put")
    }

    func testDroppingAnActionOntoItselfDoesNothing() {
        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "action.1", target: standalone("action.1")))
    }

    func testDroppingOntoAMemberJoinsTheGroupItIsIn() {
        coordinator.createGroup(title: "Pair", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id
        let member = OutlineNode(id: "action.2", kind: .groupMember(action: action("action.2"), parentGroupID: groupID))

        XCTAssertEqual(
            outlineCoordinator.dropOntoOutcome(draggedID: "action.3", target: member),
            .joinGroup(id: groupID, afterMemberID: "action.2")
        )
    }

    func testDroppingAMemberOntoItsOwnSiblingIsAReorderNotAGrouping() {
        coordinator.createGroup(title: "Pair", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id
        let sibling = OutlineNode(id: "action.2", kind: .groupMember(action: action("action.2"), parentGroupID: groupID))

        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "action.1", target: sibling),
                     "both are already in the same group, so there is nothing to group")
    }

    func testAnExtensionsOwnRowsCannotTakeADrop() {
        let packageChrome = ActionChrome(
            badge: .extensionPkg("JWT"),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: "com.openclip.jwt")
        )
        let command = DummyAction(id: "com.openclip.jwt.inspect", title: "Inspect", chrome: packageChrome)
        coordinator.register(action: command)

        let subAction = OutlineNode(
            id: command.id,
            kind: .extensionSubAction(action: command, parentGroupID: "com.openclip.jwt.jwt")
        )
        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "action.1", target: subAction))

        let header = OutlineNode(
            id: "pkg.com.openclip.jwt",
            kind: .packageHeader(packageID: "com.openclip.jwt", title: "JWT", gatedReason: nil)
        )
        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "action.1", target: header))
    }

    func testAnIneligibleActionIsNeverGrouped() {
        let aiTools = DummyAction(
            id: "builtin.aiTools",
            title: "AI Tools",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .showSubActions, source: .builtin)
        )
        coordinator.register(action: aiTools)

        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "builtin.aiTools", target: standalone("action.1")),
                     "dragging something that cannot be grouped")
        XCTAssertNil(
            outlineCoordinator.dropOntoOutcome(
                draggedID: "action.1",
                target: OutlineNode(id: aiTools.id, kind: .standaloneAction(aiTools))
            ),
            "dropping onto something that cannot be grouped"
        )
    }

    func testCustomGroupMemberReorderingValidateDropReturnsMove() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        _ = outlineCoordinator.rebuildTree()
        let groupID = coordinator.actionGroupDefs[0].id
        guard let groupNode = outlineCoordinator.rootNodes.first(where: { $0.id == groupID }) else {
            return XCTFail("Group node not found")
        }

        let outlineView = NSOutlineView()
        let info = MockDraggingInfo(actionID: "action.3")
        let op = outlineCoordinator.outlineView(outlineView, validateDrop: info, proposedItem: groupNode, proposedChildIndex: 0)
        XCTAssertEqual(op, .move, "Reordering a member inside its own group should return .move")
    }

    func testCustomGroupMemberReorderingAcceptDropUpdatesOrder() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        _ = outlineCoordinator.rebuildTree()
        let groupID = coordinator.actionGroupDefs[0].id
        guard let groupNode = outlineCoordinator.rootNodes.first(where: { $0.id == groupID }) else {
            return XCTFail("Group node not found")
        }

        let outlineView = NSOutlineView()
        let info = MockDraggingInfo(actionID: "action.3")
        let success = outlineCoordinator.outlineView(outlineView, acceptDrop: info, item: groupNode, childIndex: 0)
        XCTAssertTrue(success)

        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.3", "action.1", "action.2"])
        XCTAssertEqual(coordinator.actions.map(\.id), [groupID, "action.3", "action.1", "action.2", "action.4"])
    }

    func testOutlineNodeSignatureDistinguishesDisabledState() {
        let dummy = DummyAction(id: "com.pkg.leafy.1", title: "Leafy 1")
        let customization = ActionCustomizationManager(settingsStore: settingsStore)

        let nodeEnabled = OutlineNode(
            id: dummy.id,
            kind: .standaloneAction(dummy),
            customization: customization,
            disabledActionIDs: [],
            disabledPackages: []
        )
        let nodeDisabled = OutlineNode(
            id: dummy.id,
            kind: .standaloneAction(dummy),
            customization: customization,
            disabledActionIDs: [dummy.id],
            disabledPackages: []
        )
        let nodePkgDisabled = OutlineNode(
            id: dummy.id,
            kind: .standaloneAction(dummy),
            customization: customization,
            disabledActionIDs: [],
            disabledPackages: ["com.pkg.leafy"]
        )

        XCTAssertNotEqual(nodeEnabled.signature, nodeDisabled.signature)
        XCTAssertNotEqual(nodeEnabled.signature, nodePkgDisabled.signature)
        XCTAssertFalse(OutlineNode.treesEqual([nodeEnabled], [nodeDisabled]))
        XCTAssertFalse(OutlineNode.treesEqual([nodeEnabled], [nodePkgDisabled]))
    }

    func testActionEnablementToggleIndividualActionInsideDisabledPackage() {
        var disabledPackages: Set<String> = ["com.pkg.leafy"]
        var disabledActionIDs: Set<String> = []

        let action1 = DummyAction(id: "action.1", title: "Action 1")
        let binding1 = ActionEnablement.binding(
            for: action1,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(binding1.wrappedValue)

        // Turn action 1 on: package should be removed from disabledPackages, and siblings should be disabled
        binding1.wrappedValue = true

        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertFalse(disabledActionIDs.contains("action.1"))
        // Siblings (action.2, action.3, action.4 from setUp) should now be in disabledActionIDs
        XCTAssertTrue(disabledActionIDs.contains("action.2"))
        XCTAssertTrue(disabledActionIDs.contains("action.3"))
        XCTAssertTrue(disabledActionIDs.contains("action.4"))

        XCTAssertTrue(binding1.wrappedValue)

        binding1.wrappedValue = false
        XCTAssertTrue(disabledActionIDs.contains("action.1"))
        XCTAssertFalse(binding1.wrappedValue)
    }

    func testPackageBindingEnableAndDisable() {
        var disabledPackages: Set<String> = []
        var disabledActionIDs: Set<String> = ["action.1", "action.2", "action.3", "action.4"]

        let pkgBinding = ActionEnablement.packageBinding(
            packageID: "com.pkg.leafy",
            gatedReason: nil,
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            coordinator: coordinator
        )

        // When all actions are disabled, package reads as false
        XCTAssertFalse(pkgBinding.wrappedValue)

        // Turn package on: clears all action disables and clears disabledPackages
        pkgBinding.wrappedValue = true
        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertTrue(disabledActionIDs.isEmpty)
        XCTAssertTrue(pkgBinding.wrappedValue)

        // Turn package off: adds to disabledPackages
        pkgBinding.wrappedValue = false
        XCTAssertTrue(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertFalse(pkgBinding.wrappedValue)
    }

    func testActionEnablementCannotEnableChildOfDisabledExtensionGroup() {
        let group1 = DummyAction(
            id: "com.pkg.leafy.g1",
            title: "Group 1",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let group2 = DummyAction(
            id: "com.pkg.leafy.g2",
            title: "Group 2",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child2 = DummyAction(
            id: "com.pkg.leafy.g2.child",
            title: "Child 2",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        coordinator.register(action: group1)
        coordinator.register(action: group2)
        coordinator.register(action: child2)

        var disabledPackages: Set<String> = []
        var disabledActionIDs: Set<String> = ["com.pkg.leafy.g1", "com.pkg.leafy.g2", "com.pkg.leafy.g2.child"]

        let childBinding = ActionEnablement.binding(
            for: child2,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(childBinding.wrappedValue)
        childBinding.wrappedValue = true

        XCTAssertEqual(disabledActionIDs, ["com.pkg.leafy.g1", "com.pkg.leafy.g2", "com.pkg.leafy.g2.child"])
        XCTAssertFalse(childBinding.wrappedValue)
    }

    func testDisabledCustomGroupMakesChildrenOffWithoutChangingTheirPreferences() {
        coordinator.createGroup(title: "Tools", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id
        var disabledIDs: Set<String> = [groupID, "action.2"]
        let disabledBinding = Binding(get: { disabledIDs }, set: { disabledIDs = $0 })
        let child = ActionEnablement.binding(
            for: action("action.1"), disabledActionIDs: disabledBinding,
            disabledPackages: .constant([]), coordinator: coordinator
        )
        let optedOutChild = ActionEnablement.binding(
            for: action("action.2"), disabledActionIDs: disabledBinding,
            disabledPackages: .constant([]), coordinator: coordinator
        )
        let group = ActionEnablement.binding(
            for: action(groupID), disabledActionIDs: disabledBinding,
            disabledPackages: .constant([]), coordinator: coordinator
        )

        XCTAssertFalse(child.wrappedValue)
        child.wrappedValue = true
        optedOutChild.wrappedValue = false
        XCTAssertEqual(disabledIDs, [groupID, "action.2"])

        group.wrappedValue = true
        XCTAssertTrue(child.wrappedValue)
        XCTAssertFalse(optedOutChild.wrappedValue)
        XCTAssertEqual(disabledIDs, ["action.2"])
    }

    func testExtensionGroupRoundTripPreservesIndividualChildChoices() {
        let package = "com.pkg.leafy"
        let group = DummyAction(
            id: package + ".group", title: "Tools",
            chrome: ActionChrome(popupBehavior: .showSubActions, source: .extensionPkg(packageID: package))
        )
        let child = DummyAction(id: group.id + ".enabled", title: "Enabled")
        let optedOut = DummyAction(id: group.id + ".disabled", title: "Disabled")
        coordinator.register(action: group)
        coordinator.register(action: child)
        coordinator.register(action: optedOut)
        var disabledIDs: Set<String> = [group.id, optedOut.id]
        let disabledBinding = Binding(get: { disabledIDs }, set: { disabledIDs = $0 })
        let parent = ActionEnablement.binding(
            for: group, disabledActionIDs: disabledBinding,
            disabledPackages: .constant([]), coordinator: coordinator
        )
        let childBinding = ActionEnablement.binding(
            for: child, disabledActionIDs: disabledBinding,
            disabledPackages: .constant([]), coordinator: coordinator
        )

        XCTAssertFalse(childBinding.wrappedValue)
        childBinding.wrappedValue = true
        XCTAssertEqual(disabledIDs, [group.id, optedOut.id])
        parent.wrappedValue = true
        XCTAssertTrue(childBinding.wrappedValue)
        XCTAssertEqual(disabledIDs, [optedOut.id])
        parent.wrappedValue = false
        XCTAssertFalse(childBinding.wrappedValue)
        parent.wrappedValue = true
        XCTAssertEqual(disabledIDs, [optedOut.id])
    }

    func testDisabledGroupPackageBlocksChildButLeavesParentSwitchAvailable() {
        let group = DummyAction(
            id: "com.pkg.leafy.group", title: "Tools",
            chrome: ActionChrome(popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child = DummyAction(id: group.id + ".child", title: "Child")
        coordinator.register(action: group)
        coordinator.register(action: child)
        var disabledPackages: Set<String> = ["com.pkg.leafy"]
        var disabledIDs: Set<String> = []
        let packageBinding = Binding(get: { disabledPackages }, set: { disabledPackages = $0 })
        let disabledBinding = Binding(get: { disabledIDs }, set: { disabledIDs = $0 })
        let childBinding = ActionEnablement.binding(
            for: child, disabledActionIDs: disabledBinding,
            disabledPackages: packageBinding, coordinator: coordinator
        )
        let parentBinding = ActionEnablement.binding(
            for: group, disabledActionIDs: disabledBinding,
            disabledPackages: packageBinding, coordinator: coordinator
        )

        childBinding.wrappedValue = true
        XCTAssertEqual(disabledPackages, ["com.pkg.leafy"])
        XCTAssertFalse(childBinding.wrappedValue)
        parentBinding.wrappedValue = true
        XCTAssertTrue(disabledPackages.isEmpty)
        XCTAssertTrue(childBinding.wrappedValue)
    }

    func testChildOutlineSignatureChangesWhenParentGroupIsDisabled() {
        let child = action("action.1")
        let customization = ActionCustomizationManager(settingsStore: settingsStore)
        for kind in [
            OutlineNode.Kind.groupMember(action: child, parentGroupID: "group.tools"),
            OutlineNode.Kind.extensionSubAction(action: child, parentGroupID: "group.tools")
        ] {
            let enabled = OutlineNode(id: child.id, kind: kind, customization: customization)
            let disabled = OutlineNode(
                id: child.id, kind: kind, customization: customization,
                disabledActionIDs: ["group.tools"]
            )
            XCTAssertNotEqual(enabled.signature, disabled.signature)
        }
    }

    func testChildSwitchReflectsParentStateAcrossSettingsRows() throws {
        coordinator.createGroup(title: "Tools", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id
        let child = action("action.1")
        let customization = ActionCustomizationManager(settingsStore: settingsStore)
        func findSwitch(in view: NSView) -> NSSwitch? {
            if let control = view as? NSSwitch { return control }
            return view.subviews.lazy.compactMap { findSwitch(in: $0) }.first
        }

        let states: [(disabledIDs: Set<String>, isOn: Bool, canToggle: Bool)] = [
            ([groupID], false, false), ([], true, true), ([child.id], false, true)
        ]
        for state in states {
            let views = [
                AnyView(ActionRowView(
                    action: child,
                    presentationModel: customization.presented(child, surface: .table),
                    disabledActionIDs: .constant(state.disabledIDs),
                    disabledPackages: .constant([]), coordinator: coordinator
                )),
                AnyView(ActionSettingsRow(
                    action: child, disabledActionIDs: .constant(state.disabledIDs),
                    disabledPackages: .constant([]), coordinator: coordinator
                ))
            ]
            for view in views {
                for scheme in [ColorScheme.light, .dark] {
                    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).frame(width: 600, height: 40))
                    host.frame = NSRect(x: 0, y: 0, width: 600, height: 40)
                    host.layoutSubtreeIfNeeded()
                    let control = try XCTUnwrap(findSwitch(in: host))
                    XCTAssertEqual(control.state, state.isOn ? .on : .off)
                    XCTAssertEqual(control.isEnabled, state.canToggle)
                }
            }
        }
    }

    func testActionEnablementToggleGroupContainerKeepsChildCommandsEnabled() {
        let group = DummyAction(
            id: "com.pkg.leafy.g1",
            title: "Group 1",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child1 = DummyAction(
            id: "com.pkg.leafy.g1.c1",
            title: "Child 1",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child2 = DummyAction(
            id: "com.pkg.leafy.g1.c2",
            title: "Child 2",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let standalone = DummyAction(
            id: "com.pkg.leafy.standalone",
            title: "Standalone",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        coordinator.register(action: group)
        coordinator.register(action: child1)
        coordinator.register(action: child2)
        coordinator.register(action: standalone)

        var disabledPackages: Set<String> = ["com.pkg.leafy"]
        var disabledActionIDs: Set<String> = []

        let groupBinding = ActionEnablement.binding(
            for: group,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(groupBinding.wrappedValue)
        groupBinding.wrappedValue = true

        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1"))
        // Group children must NOT be disabled
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1.c1"))
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1.c2"))
        // Sibling outside the group is disabled
        XCTAssertTrue(disabledActionIDs.contains("com.pkg.leafy.standalone"))
        XCTAssertTrue(groupBinding.wrappedValue)
    }

    func testAcceptDropBeforePackageHeaderPlacesActionBeforePackageActions() {
        _ = outlineCoordinator.rebuildTree()
        let standaloneAction = DummyAction(
            id: "standalone.other",
            title: "Other",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        coordinator.register(action: standaloneAction)
        _ = outlineCoordinator.rebuildTree()

        guard let headerIndex = outlineCoordinator.rootNodes.firstIndex(where: { $0.id == "pkg.com.pkg.leafy" }) else {
            return XCTFail("Package header node not found")
        }

        let outlineView = NSOutlineView()
        let info = MockDraggingInfo(actionID: "standalone.other")
        let success = outlineCoordinator.outlineView(outlineView, acceptDrop: info, item: nil, childIndex: headerIndex)
        XCTAssertTrue(success)

        XCTAssertEqual(coordinator.actions.first?.id, "standalone.other")
    }
}

private final class MockDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .every
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint = .zero
    var draggedImage: NSImage?
    let draggingPasteboard: NSPasteboard

    @MainActor
    convenience init(actionID: String) {
        self.init(actionIDs: [actionID])
    }

    @MainActor
    init(actionIDs: [String]) {
        let pb = NSPasteboard.withUniqueName()
        let items = actionIDs.map { id in
            let item = NSPasteboardItem()
            item.setString(id, forType: NSPasteboard.PasteboardType("com.openclip.action-id"))
            return item
        }
        pb.writeObjects(items)
        self.draggingPasteboard = pb
    }

    var draggingSource: Any?
    var draggingSequenceNumber: Int = 0
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight = .none
    func resetSpringLoading() {}
}
