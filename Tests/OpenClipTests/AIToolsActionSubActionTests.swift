import XCTest
import SwiftUI
@testable import OpenClip
@testable import Core

/// Minimal fake action with a configurable chrome source, for AIToolsAction's children resolution.
private struct FakeAIAction: Action {
    let id: String
    var title: String { id }
    var icon: ActionIcon { .symbol("sparkles") }
    var chrome: ActionChrome
    var enabled: Bool
    init(id: String, source: ActionChrome.Source = .ai, enabled: Bool = true) {
        self.id = id
        self.chrome = ActionChrome(source: source)
        self.enabled = enabled
    }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { enabled }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

@MainActor
final class AIToolsActionSubActionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    func testStandalonePresetsAreNotDuplicatedInAITools() {
        let store = MemorySettingsStore()
        let tools = AIToolsAction(settingsStore: store)
        let presets = [FakeAIAction(id: "ai.preset.1"), FakeAIAction(id: "ai.preset.2")]
        store.set(.standaloneAIActionIDs, value: ["ai.preset.1"])
        XCTAssertEqual(tools.subActions(in: presets).map(\.id), ["ai.preset.2"])
        store.set(.standaloneAIActionIDs, value: Set(presets.map(\.id)))
        XCTAssertTrue(tools.subActions(in: presets).isEmpty, "An empty group must not resurrect presets via the fallback.")
    }

    @MainActor
    func testAIToolsResolvesAIPresets() {
        let tools = AIToolsAction(settingsStore: MemorySettingsStore())
        let preset1 = FakeAIAction(id: "ai.preset.1")
        let preset2 = FakeAIAction(id: "ai.preset.2")
        let other = FakeAIAction(id: "builtin.copy", source: .builtin)
        let ids = tools.subActions(in: [preset1, preset2, other]).map(\.id)
        XCTAssertEqual(ids, ["ai.preset.1", "ai.preset.2"])
    }

    @MainActor
    func testEmptyCatalogDoesNotResurrectFilteredPresets() {
        let tools = AIToolsAction(settingsStore: MemorySettingsStore())
        let other = FakeAIAction(id: "builtin.copy", source: .builtin)
        let subActions = tools.subActions(in: [other])
        XCTAssertTrue(subActions.isEmpty)
    }

    private var context: ActionContext {
        ActionContext(selection: SelectionContext(
            text: "Example", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default
        ))
    }

    func testMovingAllPresetsOutAndBackRestoresSubBarWithOtherPresetsStillStandalone() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: store)
        let tools = AIToolsAction(settingsStore: store)
        let presets = [FakeAIAction(id: "ai.preset.1"), FakeAIAction(id: "ai.preset.2")]
        registry.register(builtIns: [tools] + presets)

        func displayedIDs() -> [String] {
            PopupView(actions: registry.availableActions(for: context), context: context, onResult: { _ in })
                .displayActions.map(\.id)
        }
        XCTAssertEqual(displayedIDs(), [tools.id])
        coordinator.setAIActionPlacement(actionIDs: presets.map(\.id), standalone: true)
        XCTAssertEqual(Set(displayedIDs()), Set(presets.map(\.id)))
        coordinator.setAIActionPlacement(actionIDs: [presets[0].id], standalone: false)
        XCTAssertEqual(Set(displayedIDs()), [tools.id, presets[1].id])
        XCTAssertEqual(tools.subActions(in: registry.availableActions(for: context)).map(\.id), [presets[0].id])
        coordinator.setAIActionPlacement(actionIDs: [presets[1].id], standalone: false)
        XCTAssertEqual(displayedIDs(), [tools.id])
        XCTAssertEqual(tools.subActions(in: registry.availableActions(for: context)).map(\.id), presets.map(\.id))
    }

    func testHidingAIGroupDoesNotDisableStandalonePresetsOrAIService() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let tools = AIToolsAction(settingsStore: store)
        store.set(.standaloneAIActionIDs, value: ["ai.preset.2"])
        registry.register(builtIns: [tools, FakeAIAction(id: "ai.preset.1"), FakeAIAction(id: "ai.preset.2")])
        let toggle = ActionEnablement.binding(
            for: tools,
            disabledActionIDs: Binding(get: { store.get(.disabledActionIDs) }, set: { store.set(.disabledActionIDs, value: $0) }),
            disabledPackages: .constant([])
        )
        let globalAIEnabled = AIServiceManager.shared.isAIEnabled
        toggle.wrappedValue = false
        XCTAssertFalse(toggle.wrappedValue)
        XCTAssertEqual(store.get(.disabledActionIDs), [tools.id])
        XCTAssertEqual(AIServiceManager.shared.isAIEnabled, globalAIEnabled)
        XCTAssertEqual(registry.availableActions(for: context).map(\.id), ["ai.preset.2"])
        XCTAssertEqual(registry.searchCatalog(for: context).map(\.id), ["ai.preset.2"])
        toggle.wrappedValue = true
        XCTAssertEqual(tools.subActions(in: registry.availableActions(for: context)).map(\.id), ["ai.preset.1"])
    }

    // MARK: - #175: sub-bar and scoped palette follow the Actions page arrangement

    private func makeAIGroup(_ presetIDs: [String]) -> (MemorySettingsStore, ActionRegistry, ActionCoordinator, AIToolsAction) {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: store)
        let tools = AIToolsAction(settingsStore: store)
        registry.register(builtIns: [tools] + presetIDs.map { FakeAIAction(id: $0) })
        return (store, registry, coordinator, tools)
    }

    /// Children as the hover sub-bar resolves them (bar catalog) and as the click palette does (search catalog).
    private func subBarAndPaletteIDs(_ tools: AIToolsAction, _ registry: ActionRegistry) -> (subBar: [String], palette: [String]) {
        let resolver = SubActionResolver()
        return (
            resolver.subActions(of: tools, in: registry.availableActions(for: context)).map(\.id),
            resolver.subActions(of: tools, in: registry.searchCatalog(for: context)).map(\.id)
        )
    }

    func testReorderedPresetsShowInArrangedOrderOnSubBarAndPalette() {
        let (_, registry, coordinator, tools) = makeAIGroup(["ai.preset.1", "ai.preset.2", "ai.preset.3"])
        coordinator.setExtensionGroupMemberOrder(groupID: tools.id, memberIDs: ["ai.preset.3", "ai.preset.1", "ai.preset.2"])
        let ids = subBarAndPaletteIDs(tools, registry)
        XCTAssertEqual(ids.subBar, ["ai.preset.3", "ai.preset.1", "ai.preset.2"])
        XCTAssertEqual(ids.palette, ["ai.preset.3", "ai.preset.1", "ai.preset.2"])
    }

    func testArrangedOrderWinsOverCatalogOrder() {
        let store = MemorySettingsStore()
        let tools = AIToolsAction(settingsStore: store)
        store.set(.extensionGroupMemberOrder, value: [tools.id: ["ai.preset.2", "ai.preset.1"]])
        let catalog = [FakeAIAction(id: "ai.preset.1"), FakeAIAction(id: "ai.preset.3"), FakeAIAction(id: "ai.preset.2")]
        // Unarranged presets keep their catalog position after the arranged ones.
        XCTAssertEqual(tools.subActions(in: catalog).map(\.id), ["ai.preset.2", "ai.preset.1", "ai.preset.3"])
    }

    func testMovedOutPresetLeavesSubBarAndPalette() {
        let (_, registry, coordinator, tools) = makeAIGroup(["ai.preset.1", "ai.preset.2", "ai.preset.3"])
        coordinator.setExtensionGroupMemberOrder(groupID: tools.id, memberIDs: ["ai.preset.3", "ai.preset.2", "ai.preset.1"])
        coordinator.setAIActionPlacement(actionIDs: ["ai.preset.2"], standalone: true)
        let ids = subBarAndPaletteIDs(tools, registry)
        XCTAssertEqual(ids.subBar, ["ai.preset.3", "ai.preset.1"])
        XCTAssertEqual(ids.palette, ["ai.preset.3", "ai.preset.1"])
    }

    func testMovedInPresetShowsAtItsArrangedSpotOnSubBarAndPalette() {
        let (_, registry, coordinator, tools) = makeAIGroup(["ai.preset.1", "ai.preset.2", "ai.preset.3"])
        coordinator.setAIActionPlacement(actionIDs: ["ai.preset.3"], standalone: true)
        XCTAssertEqual(subBarAndPaletteIDs(tools, registry).subBar, ["ai.preset.1", "ai.preset.2"])
        // Dropped back into the group between the other two.
        coordinator.setAIActionPlacement(actionIDs: ["ai.preset.3"], standalone: false)
        coordinator.setExtensionGroupMemberOrder(groupID: tools.id, memberIDs: ["ai.preset.1", "ai.preset.3", "ai.preset.2"])
        let ids = subBarAndPaletteIDs(tools, registry)
        XCTAssertEqual(ids.subBar, ["ai.preset.1", "ai.preset.3", "ai.preset.2"])
        XCTAssertEqual(ids.palette, ["ai.preset.1", "ai.preset.3", "ai.preset.2"])
    }

    func testGroupDisappearsWhenAllRemainingPresetsAreDisabled() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let tools = AIToolsAction(settingsStore: store)
        registry.register(builtIns: [tools, FakeAIAction(id: "ai.preset.1", enabled: false)])
        let available = registry.availableActions(for: context)
        XCTAssertTrue(tools.subActions(in: available).isEmpty)
        XCTAssertTrue(PopupView(actions: available, context: context, onResult: { _ in }).displayActions.isEmpty)
    }
}
