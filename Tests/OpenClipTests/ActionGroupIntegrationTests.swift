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

    func testUninstallExtensionInsideGroupUsesCanonicalIDAndDisbandsGroup() async throws {
        let extAction1 = CustomAction(id: "com.custom.ext1", title: "Ext 1", iconName: "star", type: .textSnippet(template: "1"))
        let extAction2 = CustomAction(id: "com.custom.ext2", title: "Ext 2", iconName: "star", type: .textSnippet(template: "2"))
        coordinator.register(action: extAction1)
        coordinator.register(action: extAction2)

        coordinator.createGroup(title: "My Custom Exts", iconName: "folder", memberActionIDs: ["com.custom.ext1", "com.custom.ext2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)

        // Simulating unregister of canonical ID
        coordinator.unregister(actionID: "com.custom.ext1")

        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty, "Group must disband when member drops below 2")
        XCTAssertEqual(coordinator.actions.map(\.id), ["com.custom.ext2"])
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

    func testRemoveMemberViaCoordinatorLeavesRemainingMembersAtTopLevelWhenDisbanded() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        coordinator.register(action: a1)
        coordinator.register(action: a2)

        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.removeFromGroup(actionID: "action.1", groupID: groupID)
        XCTAssertTrue(coordinator.actionGroupDefs.isEmpty, "Group must disband when < 2 members remain")
        XCTAssertEqual(coordinator.actions.map(\.id), ["action.1", "action.2"])
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
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
