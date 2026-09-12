import XCTest
@testable import Core

@MainActor
final class ActionCoordinatorGroupTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var coordinator: ActionCoordinator!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
        coordinator.register(action: DummyAction(id: "action.1", title: "Action 1"))
        coordinator.register(action: DummyAction(id: "action.2", title: "Action 2"))
        coordinator.register(action: DummyAction(id: "action.3", title: "Action 3"))
        coordinator.register(action: DummyAction(id: "action.4", title: "Action 4"))
        coordinator.register(action: DummyAction(id: "action.5", title: "Action 5"))
    }

    /// A group is a container for actions, so an empty one is a row in the popup bar that opens
    /// onto nothing. It is not kept, whichever way it came to be empty.
    func testAGroupWithNoMembersIsNotKept() {
        XCTAssertNil(coordinator.createGroup(title: "Empty", iconName: "folder", memberActionIDs: []))
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)

        // Same when every id handed over turns out to be ineligible.
        XCTAssertNil(coordinator.createGroup(title: "Junk", iconName: "folder", memberActionIDs: ["", " ", "nope"]))
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
    }

    func testCreateGroupWithSingleMember() {
        let id = coordinator.createGroup(title: "Single", iconName: "folder", memberActionIDs: ["action.1"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(id, coordinator.actionGroupDefs.first?.id, "the caller is told which group it made")
        XCTAssertEqual(coordinator.actionGroupDefs.first?.memberActionIDs, ["action.1"])
        XCTAssertEqual(coordinator.actionGroupDefs.first?.title, "Single")
    }

    func testCreateGroupDedupesAndFiltersEmptyActionIDs() {
        coordinator.createGroup(title: "Duplicates", iconName: "folder", memberActionIDs: ["action.1", "action.1", "", " "])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs.first?.memberActionIDs, ["action.1"])

        coordinator.createGroup(title: "Deduped Valid", iconName: "folder", memberActionIDs: ["action.2", "action.3", "action.2", ""])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.last?.memberActionIDs, ["action.2", "action.3"])
    }

    func testCreateGroupRemovesMembersFromExistingGroupsAndDropsOneItEmpties() {
        // Create Group 1 with actions 1, 2, 3
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let group1ID = coordinator.actionGroupDefs[0].id

        // Create Group 2 with action 1 and 4 -> action 1 moves to Group 2; Group 1 retains 2, 3
        coordinator.createGroup(title: "Group 2", iconName: "folder.fill", memberActionIDs: ["action.1", "action.4"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, ["action.2", "action.3"])

        // Create Group 3 with action 2 and 3 -> Group 1 has nothing left, so it goes
        coordinator.createGroup(title: "Group 3", iconName: "star", memberActionIDs: ["action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertNil(coordinator.actionGroupDefs.first(where: { $0.id == group1ID }))
    }

    func testUpdateGroupUpdatesMetadataAndMembers() {
        coordinator.createGroup(title: "Original", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.updateGroup(groupID: groupID, title: "Updated", iconName: "star", memberActionIDs: ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].title, "Updated")
        XCTAssertEqual(coordinator.actionGroupDefs[0].iconName, "star")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "action.3"])
    }

    func testUpdateGroupKeepsGroupWithFewerThanTwoMembers() {
        coordinator.createGroup(title: "Original", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.updateGroup(groupID: groupID, title: "Updated", iconName: "folder", memberActionIDs: ["action.1"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1"])
    }

    func testUngroupRemovesGroupDef() {
        coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.ungroup(groupID: groupID)
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
    }

    /// Taking the last action out of a group takes the group with it — this is what dragging the
    /// last row out to the top level does.
    func testRemovingTheLastMemberRemovesTheGroup() {
        coordinator.createGroup(title: "Valid", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.removeFromGroup(actionID: "action.1", groupID: groupID)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1, "one left, so the group stays")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.2"])

        coordinator.removeFromGroup(actionID: "action.2", groupID: groupID)
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty, "nothing left, so neither is the group")
        XCTAssertEqual(ActionGroupDef.decodeOrEmpty(from: settingsStore.get(.actionGroups)).count, 0,
                       "and that is what is persisted")
    }

    /// Dragging the last member straight into another group counts as taking it out too.
    func testMovingTheLastMemberToAnotherGroupRemovesTheEmptiedOne() {
        coordinator.createGroup(title: "Source", iconName: "folder", memberActionIDs: ["action.1"])
        coordinator.createGroup(title: "Target", iconName: "star", memberActionIDs: ["action.2", "action.3"])
        let sourceID = coordinator.actionGroupDefs.first(where: { $0.title == "Source" })!.id
        let targetID = coordinator.actionGroupDefs.first(where: { $0.title == "Target" })!.id

        coordinator.addToGroup(actionID: "action.1", groupID: targetID)

        XCTAssertNil(coordinator.actionGroupDefs.first(where: { $0.id == sourceID }))
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == targetID })?.memberActionIDs,
                       ["action.2", "action.3", "action.1"])
    }

    func testUnregisterExtensionRetainsGroupMembershipInDefs() {
        coordinator.createGroup(title: "Valid", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        coordinator.unregister(actionID: "action.1")

        // Group definitions persist intact
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2"])

        // Re-registering action restores it in group without mutating definitions
        coordinator.register(action: DummyAction(id: "action.1", title: "Action 1"))
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2"])
    }

    func testLoadGroupDefsPreservesAllGroupMembersEvenIfTemporarilyUnregistered() throws {
        let defA = ActionGroupDef(id: "vgroup.a", title: "Group A", iconName: "folder", memberActionIDs: ["action.1", "action.2", "nonexistent.1"])
        let defB = ActionGroupDef(id: "vgroup.b", title: "Group B", iconName: "folder", memberActionIDs: ["action.3", "nonexistent.2"])
        let data = try ActionGroupDef.encode([defA, defB])
        settingsStore.set(.actionGroups, value: data)

        coordinator.loadGroupDefs()

        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs[0].id, "vgroup.a")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "nonexistent.1"])
        XCTAssertEqual(coordinator.actionGroupDefs[1].id, "vgroup.b")
        XCTAssertEqual(coordinator.actionGroupDefs[1].memberActionIDs, ["action.3", "nonexistent.2"])
    }

    func testResetClearsDefsAndSetting() {
        coordinator.createGroup(title: "Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertNotNil(settingsStore.get(.actionGroups))

        coordinator.reset()
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty)
        XCTAssertNil(settingsStore.get(.actionGroups))
    }

    func testAddToGroupAppendsMemberAndPersists() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.addToGroup(actionID: "action.3", groupID: groupID)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "action.3"])

        let data = settingsStore.get(.actionGroups)
        let defs = ActionGroupDef.decodeOrEmpty(from: data)
        XCTAssertEqual(defs.first?.memberActionIDs, ["action.1", "action.2", "action.3"])
    }

    func testAddToGroupRemovesFromOtherGroupWithoutDisbanding() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        coordinator.createGroup(title: "Group 2", iconName: "star", memberActionIDs: ["action.3", "action.4"])
        let group1ID = coordinator.actionGroupDefs.first(where: { $0.title == "Group 1" })!.id
        let group2ID = coordinator.actionGroupDefs.first(where: { $0.title == "Group 2" })!.id

        // Moving action.1 into Group 2 leaves Group 1 with only action.2
        coordinator.addToGroup(actionID: "action.1", groupID: group2ID)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, ["action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group2ID })?.memberActionIDs, ["action.3", "action.4", "action.1"])
    }

    func testAddToGroupInsertsAtIndex() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.addToGroup(actionID: "action.3", groupID: groupID, atIndex: 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.3", "action.2"])
    }

    func testCoordinatorPreventsIneligibleActionsFromEnteringGroup() {
        let aiTools = DummyAction(
            id: "builtin.ai_tools",
            title: "AI Tools",
            chrome: ActionChrome(popupBehavior: .perform, launchesAI: true)
        )
        let wordCompletion = DummyAction(
            id: "builtin.completion",
            title: "Word Completion",
            chrome: ActionChrome(popupBehavior: .provideCompletions)
        )
        let aiPreset = DummyAction(
            id: "preset.proofread",
            title: "Proofread",
            chrome: ActionChrome(popupBehavior: .perform, source: .ai)
        )
        coordinator.register(action: aiTools)
        coordinator.register(action: wordCompletion)
        coordinator.register(action: aiPreset)

        // Try creating group with ineligible actions
        coordinator.createGroup(
            title: "Mixed Group",
            iconName: "folder",
            memberActionIDs: ["action.1", "builtin.ai_tools", "builtin.completion", "preset.proofread"]
        )
        let group = coordinator.actionGroupDefs.first(where: { $0.title == "Mixed Group" })
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.memberActionIDs, ["action.1"])

        guard let groupID = group?.id else { return }

        // Try adding AI tools
        coordinator.addToGroup(actionID: "builtin.ai_tools", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("builtin.ai_tools"))

        // Try adding word completion
        coordinator.addToGroup(actionID: "builtin.completion", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("builtin.completion"))

        // Try adding AI preset
        coordinator.addToGroup(actionID: "preset.proofread", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("preset.proofread"))

        // Try adding another group into this group
        coordinator.createGroup(title: "Other Group", iconName: "folder", memberActionIDs: ["action.2"])
        let otherGroupID = coordinator.actionGroupDefs.first(where: { $0.title == "Other Group" })!.id
        coordinator.addToGroup(actionID: otherGroupID, groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs.first(where: { $0.id == groupID })!.memberActionIDs.contains(otherGroupID))
    }

    func testCoordinatorSyncCatalogOrderOnGroupUpdate() {
        coordinator.createGroup(title: "Reorder Group", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        guard let groupID = coordinator.actionGroupDefs.first?.id else { return XCTFail() }

        // Reverse order of members
        coordinator.updateGroup(groupID: groupID, title: "Reorder Group", iconName: "folder", memberActionIDs: ["action.3", "action.2", "action.1"])

        XCTAssertEqual(coordinator.actionGroupDefs.first?.memberActionIDs, ["action.3", "action.2", "action.1"])

        // Check catalog action order
        let catalogIDs = coordinator.actions.map(\.id)
        guard let gIndex = catalogIDs.firstIndex(of: groupID) else { return XCTFail("Group ID not found in catalog") }
        guard catalogIDs.count > gIndex + 3 else {
            return XCTFail("Expected three member entries after the group parent, got \(catalogIDs)")
        }
        XCTAssertEqual(Array(catalogIDs[(gIndex + 1)...(gIndex + 3)]), ["action.3", "action.2", "action.1"])
    }

    func testUpdateGroupRetainsUnregisteredExistingMember() {
        coordinator.createGroup(title: "Retain Test", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        guard let groupID = coordinator.actionGroupDefs.first?.id else { return XCTFail() }

        // Unregister action.1 (e.g. extension unloaded or disabled)
        coordinator.unregister(actionID: "action.1")
        XCTAssertFalse(coordinator.actions.contains(where: { $0.id == "action.1" }))

        // Update the group (e.g. renaming or reordering with action.1 still in member list)
        coordinator.updateGroup(
            groupID: groupID,
            title: "Retain Test Renamed",
            iconName: "folder",
            memberActionIDs: ["action.2", "action.1"]
        )

        // Verify that action.1 is retained even though it is currently unregistered
        let group = coordinator.actionGroupDefs.first(where: { $0.id == groupID })
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.memberActionIDs, ["action.2", "action.1"])
        XCTAssertEqual(group?.title, "Retain Test Renamed")
    }

    func testExtensionGroupPackageActionsAreIneligibleForCustomGrouping() {
        // Extension group package with a .showSubActions parent and sub-actions
        let groupParent = DummyAction(
            id: "pkg.dev.tools",
            title: "Dev Tools",
            chrome: ActionChrome(
                rowStyle: .actionGroup,
                popupBehavior: .showSubActions,
                source: .extensionPkg(packageID: "pkg.dev")
            )
        )
        let groupChild = DummyAction(
            id: "pkg.dev.format",
            title: "Format Code",
            chrome: ActionChrome(
                popupBehavior: .perform,
                source: .extensionPkg(packageID: "pkg.dev")
            )
        )
        // Standalone unaffected extension action in another package without .showSubActions
        let standaloneAction = DummyAction(
            id: "pkg.standalone.run",
            title: "Run Script",
            chrome: ActionChrome(
                popupBehavior: .perform,
                source: .extensionPkg(packageID: "pkg.standalone")
            )
        )

        coordinator.register(action: groupParent)
        coordinator.register(action: groupChild)
        coordinator.register(action: standaloneAction)

        // Sub-actions and parents from extension group package must be ineligible
        XCTAssertFalse(coordinator.isEligibleForGrouping(actionID: "pkg.dev.format"))
        XCTAssertFalse(coordinator.isEligibleForGrouping(actionID: "pkg.dev.tools"))

        // Unaffected standalone extension action must preserve eligibility
        XCTAssertTrue(coordinator.isEligibleForGrouping(actionID: "pkg.standalone.run"))

        // Attempting to create group with ineligible child should filter it out
        coordinator.createGroup(
            title: "Custom Group",
            iconName: "folder",
            memberActionIDs: ["pkg.standalone.run", "pkg.dev.format"]
        )
        let group = coordinator.actionGroupDefs.first(where: { $0.title == "Custom Group" })
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.memberActionIDs, ["pkg.standalone.run"])

        guard let groupID = group?.id else { return }

        // Attempting to addToGroup with ineligible child should be rejected
        coordinator.addToGroup(actionID: "pkg.dev.format", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("pkg.dev.format"))

        // Attempting to updateGroup with ineligible child should reject it
        coordinator.updateGroup(
            groupID: groupID,
            title: "Custom Group",
            iconName: "folder",
            memberActionIDs: ["pkg.standalone.run", "pkg.dev.format"]
        )
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["pkg.standalone.run"])
    }

    func testMemberActionIDsForCustomAndExtensionGroups() {
        // Custom group
        coordinator.createGroup(
            title: "Custom Group",
            iconName: "folder",
            memberActionIDs: ["action.1", "action.2"]
        )
        let customGroupID = coordinator.actionGroupDefs[0].id
        XCTAssertEqual(coordinator.memberActionIDs(for: customGroupID), ["action.1", "action.2"])

        // Extension group with sub-actions
        let groupParent = GroupAction(
            id: "com.test.group",
            title: "Test Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(
                rowStyle: .actionGroup,
                popupBehavior: .showSubActions,
                source: .extensionPkg(packageID: "com.test.group")
            )
        )
        let subAction1 = DummyAction(
            id: "com.test.group.sub1",
            title: "Sub 1",
            chrome: ActionChrome(
                rowStyle: .standard,
                popupBehavior: .perform,
                source: .extensionPkg(packageID: "com.test.group")
            )
        )
        let subAction2 = DummyAction(
            id: "com.test.group.sub2",
            title: "Sub 2",
            chrome: ActionChrome(
                rowStyle: .standard,
                popupBehavior: .perform,
                source: .extensionPkg(packageID: "com.test.group")
            )
        )
        coordinator.register(action: groupParent)
        coordinator.register(action: subAction1)
        coordinator.register(action: subAction2)

        XCTAssertEqual(
            coordinator.memberActionIDs(for: "com.test.group"),
            ["com.test.group.sub1", "com.test.group.sub2"]
        )

        // Non-existent group
        XCTAssertEqual(coordinator.memberActionIDs(for: "unknown.group"), [])
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome

    init(id: String, title: String, chrome: ActionChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)) {
        self.id = id
        self.title = title
        self.chrome = chrome
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
