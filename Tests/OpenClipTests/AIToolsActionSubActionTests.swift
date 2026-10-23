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

    /// Clicking AI Tools opens the same sub-bar as hovering (#175), which resolves its children via
    /// SubActionResolver in catalog order, i.e. the order arranged in Preferences.
    func testSubBarChildrenKeepCatalogOrder() {
        let tools = AIToolsAction(settingsStore: MemorySettingsStore())
        let catalog = [FakeAIAction(id: "ai.preset.3"), FakeAIAction(id: "ai.preset.1"), FakeAIAction(id: "ai.preset.2")]
        let ids = SubActionResolver().subActions(of: tools, in: catalog).map(\.id)
        XCTAssertEqual(ids, ["ai.preset.3", "ai.preset.1", "ai.preset.2"])
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
