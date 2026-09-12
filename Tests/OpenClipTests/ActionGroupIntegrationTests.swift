// ActionGroupIntegrationTests.swift
// OpenClip
//
// Integration tests covering custom action group lifecycle, extension uninstallation within groups,
// and table reordering/nesting behaviors in Preferences.
import XCTest
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

        // Group definitions persist intact
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["com.custom.ext1", "com.custom.ext2"])

        // Simulating re-registration upon reinstallation
        coordinator.register(action: extAction1)

        // Re-registered action is restored inside the group
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

        // Verify persisted setting in SettingsStore
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

    /// A group with nothing in it is not kept, so the old "make an empty group, then drag actions
    /// in" flow is gone: a group is made *from* actions, and it lasts as long as it holds one.
    func testAGroupLastsExactlyAsLongAsItHoldsSomething() throws {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        XCTAssertNil(coordinator.createGroup(title: "Empty Group", iconName: "folder", memberActionIDs: []))
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
        XCTAssertFalse(coordinator.actions.contains { $0.id.hasPrefix("vgroup.") })

        // Made from two actions — which is what dropping one onto the other does — it is real.
        let groupID = try XCTUnwrap(
            coordinator.createGroup(title: "Pair", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        )
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
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
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.2"])

        // Drag the last one out: the group goes with it, and so does its row on the bar.
        coordinator.removeFromGroup(actionID: "action.2", groupID: groupID)
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
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

        // The Customize list is the popup bar's layout and nothing else: every row type (an
        // extension group and its sub-action, a custom group and its members, a package header and
        // its actions) renders a cell, and none of them carries a switch or any other control —
        // enabling, configuring and removing all live on the action's own page.
        var renderedRows = 0
        for r in 0..<outlineView.numberOfRows {
            guard let rowView = outlineView.view(atColumn: 0, row: r, makeIfNecessary: true) else { continue }
            renderedRows += 1
            XCTAssertTrue(findSwitches(in: rowView).isEmpty, "Row \(r) must not carry a switch; the action's page owns it")
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

        // Reorder via coordinator
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

    // MARK: - Reordering inside an extension's group

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
            id: "builtin.ai_tools",
            title: "AI Tools",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .showSubActions, source: .builtin)
        )
        coordinator.register(action: aiTools)

        XCTAssertNil(outlineCoordinator.dropOntoOutcome(draggedID: "builtin.ai_tools", target: standalone("action.1")),
                     "dragging something that cannot be grouped")
        XCTAssertNil(
            outlineCoordinator.dropOntoOutcome(
                draggedID: "action.1",
                target: OutlineNode(id: aiTools.id, kind: .standaloneAction(aiTools))
            ),
            "dropping onto something that cannot be grouped"
        )
    }
}
