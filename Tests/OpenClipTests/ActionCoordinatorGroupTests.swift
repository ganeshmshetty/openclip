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

    func testCreateEmptyGroup() {
        coordinator.createGroup(title: "Empty", iconName: "folder", memberActionIDs: [])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs.first?.memberActionIDs, [])
        XCTAssertEqual(coordinator.actionGroupDefs.first?.title, "Empty")
        XCTAssertEqual(coordinator.actionGroupDefs.first?.iconName, "folder")
    }

    func testCreateGroupWithSingleMember() {
        coordinator.createGroup(title: "Single", iconName: "folder", memberActionIDs: ["action.1"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
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

    func testCreateGroupRemovesMembersFromExistingGroupsWithoutDisbanding() {
        // Create Group 1 with actions 1, 2, 3
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let group1ID = coordinator.actionGroupDefs[0].id

        // Create Group 2 with action 1 and 4 -> action 1 moves to Group 2; Group 1 retains 2, 3
        coordinator.createGroup(title: "Group 2", iconName: "folder.fill", memberActionIDs: ["action.1", "action.4"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, ["action.2", "action.3"])

        // Create Group 3 with action 2 and 3 -> Group 1 is now empty but remains
        coordinator.createGroup(title: "Group 3", iconName: "star", memberActionIDs: ["action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 3)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, [])
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

    func testRemoveMemberKeepsGroupDefWhenEmpty() {
        coordinator.createGroup(title: "Valid", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)

        coordinator.removeFromGroup(actionID: "action.1", groupID: coordinator.actionGroupDefs[0].id)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.2"])

        // Removing the last member leaves 0 members -> group remains
        coordinator.removeFromGroup(actionID: "action.2", groupID: coordinator.actionGroupDefs[0].id)
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, [])
    }

    func testUnregisterExtensionPrunesMemberAndRetainsGroupDef() {
        coordinator.createGroup(title: "Valid", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        coordinator.unregister(actionID: "action.1")

        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.2"])
    }

    func testLoadGroupDefsPrunesOrphanActionIDs() throws {
        let defA = ActionGroupDef(id: "vgroup.a", title: "Group A", iconName: "folder", memberActionIDs: ["action.1", "action.2", "nonexistent.1"])
        let defB = ActionGroupDef(id: "vgroup.b", title: "Group B", iconName: "folder", memberActionIDs: ["action.3", "nonexistent.2"])
        let data = try ActionGroupDef.encode([defA, defB])
        settingsStore.set(.actionGroups, value: data)

        coordinator.loadGroupDefs()

        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs[0].id, "vgroup.a")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs[1].id, "vgroup.b")
        XCTAssertEqual(coordinator.actionGroupDefs[1].memberActionIDs, ["action.3"])
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
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
