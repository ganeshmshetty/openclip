import XCTest
@testable import Core

@MainActor
final class ActionRegistryGroupTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
    }

    func testSortActionsInjectsGroupHeaderAndKeepsMembersInActions() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        registry.register(builtIns: [a1, a2, a3])

        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.3"])
        registry.setGroupDefs([def])

        // actions: [vgroup.g1, action.1, action.3, action.2]
        // Group header injected at first member; members gathered contiguously; ungrouped actions follow.
        let ids = registry.actions.map(\.id)
        XCTAssertEqual(ids[0], "vgroup.g1")
        XCTAssertEqual(ids, ["vgroup.g1", "action.1", "action.3", "action.2"])
        XCTAssertTrue(ids.contains("action.1"), "Grouped members must stay in actions with canonical IDs")
        XCTAssertTrue(ids.contains("action.3"), "Grouped members must stay in actions with canonical IDs")
        XCTAssertTrue(ids.contains("action.2"), "Non-grouped actions must remain")

        guard let groupAction = registry.actions.first(where: { $0.id == "vgroup.g1" }) as? CustomGroupAction else {
            return XCTFail("Expected CustomGroupAction")
        }
        let subActions = groupAction.subActions(in: registry.actions)
        XCTAssertEqual(subActions.map(\.id), ["action.1", "action.3"])
    }

    func testSubActionsPreservesCatalogSortOrderWhenMemberActionIDsDiffer() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        registry.register(builtIns: [a1, a2, a3])

        // User explicit order: action.3 comes before action.1
        settingsStore.set(.actionOrder, value: ["action.3", "action.1", "action.2"])

        // Group definition has memberActionIDs in opposite order: action.1, action.3
        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.3"])
        registry.setGroupDefs([def])

        guard let groupAction = registry.actions.first(where: { $0.id == "vgroup.g1" }) as? CustomGroupAction else {
            return XCTFail("Expected CustomGroupAction")
        }
        // Subactions in catalog should match catalog's sorted order: action.3, action.1
        let subActions = groupAction.subActions(in: registry.actions)
        XCTAssertEqual(subActions.map(\.id), ["action.3", "action.1"])
    }

    func testAvailableActionsHidesCustomGroupMembersWhenGroupDisabled() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        registry.register(builtIns: [a1, a2])

        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        registry.setGroupDefs([def])

        // Disable the group
        settingsStore.set(.disabledActionIDs, value: ["vgroup.g1"])

        let selection = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection)
        let available = registry.availableActions(for: context)

        XCTAssertFalse(available.contains(where: { $0.id == "vgroup.g1" }), "Disabled group must be hidden")
        XCTAssertFalse(available.contains(where: { $0.id == "action.1" }), "Members of disabled group must be hidden")
        XCTAssertFalse(available.contains(where: { $0.id == "action.2" }), "Members of disabled group must be hidden")
    }

    func testAvailableActionsShowsGroupAndMembersWhenGroupEnabled() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        registry.register(builtIns: [a1, a2])

        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        registry.setGroupDefs([def])

        let selection = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection)
        let available = registry.availableActions(for: context)

        XCTAssertTrue(available.contains(where: { $0.id == "vgroup.g1" }), "Enabled group must be shown")
        XCTAssertTrue(available.contains(where: { $0.id == "action.1" }), "Members of enabled group must be shown")
        XCTAssertTrue(available.contains(where: { $0.id == "action.2" }), "Members of enabled group must be shown")
    }

    func testMemberOfDisabledGroupHiddenEvenIfOtherGroupEnabled() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        let a4 = DummyAction(id: "action.4", title: "Action 4")
        registry.register(builtIns: [a1, a2, a3, a4])

        let def1 = ActionGroupDef(id: "vgroup.g1", title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let def2 = ActionGroupDef(id: "vgroup.g2", title: "Group 2", iconName: "star", memberActionIDs: ["action.3", "action.4"])
        registry.setGroupDefs([def1, def2])

        settingsStore.set(.disabledActionIDs, value: ["vgroup.g1"])

        let selection = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection)
        let available = registry.availableActions(for: context)

        XCTAssertFalse(available.contains(where: { $0.id == "vgroup.g1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "action.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "action.2" }))

        XCTAssertTrue(available.contains(where: { $0.id == "vgroup.g2" }))
        XCTAssertTrue(available.contains(where: { $0.id == "action.3" }))
        XCTAssertTrue(available.contains(where: { $0.id == "action.4" }))
    }

    func testMoveActionsExcludesCustomGroupActionFromActionOrder() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        registry.register(builtIns: [a1, a2, a3])

        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        registry.setGroupDefs([def])

        // actions: [vgroup.g1, action.1, action.2, action.3]
        // Move action.3 from index 3 to index 0
        registry.moveActions(from: IndexSet(integer: 3), to: 0)

        let savedOrder = settingsStore.get(.actionOrder)
        XCTAssertFalse(savedOrder.contains("vgroup.g1"), "Synthetic group IDs must not be saved to actionOrder")
        XCTAssertEqual(savedOrder, ["action.3", "action.1", "action.2"])
    }

    func testRegisteredActionIDsReturnsOnlyBaseRegisteredActionIDs() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        registry.register(builtIns: [a1, a2])

        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        registry.setGroupDefs([def])

        XCTAssertEqual(registry.registeredActionIDs, Set(["action.1", "action.2"]))
    }

    func testSortActionsWithoutGroupsMaintainsBaseOrder() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        registry.register(builtIns: [a1, a2, a3])
        registry.setGroupDefs([])

        XCTAssertEqual(registry.actions.map(\.id), ["action.1", "action.2", "action.3"])
    }

    func testGroupWithNoRegisteredMembersAppendedAtEnd() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        registry.register(builtIns: [a1, a2])

        let def = ActionGroupDef(id: "vgroup.g1", title: "Empty Group", iconName: "folder", memberActionIDs: ["unregistered.1", "unregistered.2"])
        registry.setGroupDefs([def])

        let ids = registry.actions.map(\.id)
        XCTAssertEqual(ids, ["action.1", "action.2", "vgroup.g1"])
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
