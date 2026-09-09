import XCTest
@testable import Core

struct MockAction: Action {
    let id: String
    let title = "Mock"
    let icon = ActionIcon.symbol("star")
    let shouldBeEnabled: Bool
    let chrome: ActionChrome
    
    init(id: String, shouldBeEnabled: Bool, chrome: ActionChrome = ActionChrome()) {
        self.id = id
        self.shouldBeEnabled = shouldBeEnabled
        self.chrome = chrome
    }
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool {
        return shouldBeEnabled
    }
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult {
        return .success
    }
}

/// Stands in for the AI Tools launcher: a row that resolves its children out of the catalog
/// (`chrome.source == .ai`), exactly as `AIToolsAction` does.
struct MockLauncherAction: Action, SubActionProviding {
    let id: String
    let title = "Launcher"
    let icon = ActionIcon.symbol("sparkles")
    var chrome: ActionChrome { ActionChrome(source: .builtin, launchesAI: true) }

    @MainActor
    func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult { .success }

    @MainActor
    func subActions(in catalog: [any Action]) -> [any Action] {
        catalog.filter { ActionIdentity.isAIPreset($0) }
    }
}

final class ActionRegistryTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    @MainActor
    func testActionRegistrationAndAvailability() {
        let registry = ActionRegistry.shared
        
        let action1 = MockAction(id: "mock.1", shouldBeEnabled: true)
        let action2 = MockAction(id: "mock.2", shouldBeEnabled: false)
        
        let initialCount = registry.actions.count
        registry.register(builtIns: [action1, action2])
        
        XCTAssertEqual(registry.actions.count, initialCount + 2)
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertTrue(available.contains(where: { $0.id == "mock.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "mock.2" }))
    }
    
    func testActionContext() {
        let selection = SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: .shift)
        
        XCTAssertEqual(context.selection.text, "hello")
        XCTAssertEqual(context.modifiers, .shift)
    }
    
    @MainActor
    func testDisabledActionsAreFiltered() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        
        let action = MockAction(id: "mock.disabled.test", shouldBeEnabled: true)
        registry.register(action: action)
        
        store.set(.disabledActionIDs, value: Set(["mock.disabled.test"]))
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == "mock.disabled.test" }))
    }
    
    @MainActor
    func testDisabledPackageHidesAllPackageActions() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        
        let packageID = "com.test.pkg"
        let pkgChrome = ActionChrome(
            badge: .extensionPkg(packageID),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: packageID)
        )
        let a1 = MockAction(id: "\(packageID).action.1", shouldBeEnabled: true, chrome: pkgChrome)
        let a2 = MockAction(id: "\(packageID).action.2", shouldBeEnabled: true, chrome: pkgChrome)
        registry.register(builtIns: [a1, a2])
        
        store.set(.disabledPackages, value: Set([packageID]))
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == a1.id }))
        XCTAssertFalse(available.contains(where: { $0.id == a2.id }))
    }

    @MainActor
    func testDisabledGroupRowHidesItsSubActions() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupID = "mock.group"
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: groupID, shouldBeEnabled: true, chrome: groupChrome)
        let subA = MockAction(id: "\(groupID).a", shouldBeEnabled: true)
        let subB = MockAction(id: "\(groupID).b", shouldBeEnabled: true)
        registry.register(builtIns: [group, subA, subB])

        store.set(.disabledActionIDs, value: Set([groupID]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        XCTAssertFalse(available.contains { $0.id == groupID })
        XCTAssertFalse(available.contains { $0.id == subA.id })
        XCTAssertFalse(available.contains { $0.id == subB.id })
    }

    @MainActor
    func testEnabledGroupRowKeepsSubActionsAvailable() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupID = "mock.group.visible"
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: groupID, shouldBeEnabled: true, chrome: groupChrome)
        let sub = MockAction(id: "\(groupID).x", shouldBeEnabled: true)
        registry.register(builtIns: [group, sub])

        store.set(.disabledActionIDs, value: Set([]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        XCTAssertTrue(available.contains { $0.id == groupID })
        XCTAssertTrue(available.contains { $0.id == sub.id })
    }

    @MainActor
    func testSearchCatalogDropsContextuallyUnableAndSettingsDisabled() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: "mock.searchgroup", shouldBeEnabled: true, chrome: groupChrome)
        let sub = MockAction(id: "mock.searchgroup.a", shouldBeEnabled: true)
        let completion = MockAction(id: "builtin.completion", shouldBeEnabled: true, chrome: ActionChrome(popupBehavior: .provideCompletions))
        // Contextually unable: `isEnabled(for:)` is false, so the palette must not offer it.
        let contextuallyUnable = MockAction(id: "mock.searchdisabled", shouldBeEnabled: false)
        // Settings-disabled (`.disabledActionIDs`): a row toggled off in Preferences is not
        // offered anywhere, the palette included.
        let settingsDisabled = MockAction(id: "mock.settingsdisabled", shouldBeEnabled: true)
        let normal = MockAction(id: "mock.searchnormal", shouldBeEnabled: true)
        registry.register(builtIns: [group, sub, completion, contextuallyUnable, settingsDisabled, normal])
        store.set(.disabledActionIDs, value: Set(["mock.settingsdisabled"]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let catalog = registry.searchCatalog(for: ActionContext(selection: selection, modifiers: []))

        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup" })
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup.a" })
        XCTAssertFalse(catalog.contains { $0.id == "mock.searchdisabled" })
        XCTAssertFalse(catalog.contains { $0.id == "mock.settingsdisabled" },
                       "an action switched off in Preferences must not be offered in the palette")
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchnormal" })
        XCTAssertFalse(catalog.contains { $0.id == "builtin.completion" })
    }

    @MainActor
    func testAIChromeActionsExcludedFromBarButIncludedInSearchCatalog() {
        // Own store: `ActionRegistry()` reads the real preferences domain (the test host shares
        // OpenClip's bundle id), so a developer disabling Copy in the app would fail this test.
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let aiChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
        let aiAction = MockAction(id: "ai.preset.proofread", shouldBeEnabled: true, chrome: aiChrome)
        let normal = MockAction(id: "mock.normal", shouldBeEnabled: true)
        registry.register(builtIns: [aiAction, normal])

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        // AI preset actions never flood the popup bar (the reorderable AI Tools action is the
        // bar's entry point), but the palette still discovers them.
        XCTAssertFalse(available.contains { $0.id == "ai.preset.proofread" })
        XCTAssertTrue(available.contains { $0.id == "mock.normal" })
        XCTAssertTrue(registry.searchCatalog(for: context).contains { $0.id == "ai.preset.proofread" })
    }

    @MainActor
    func testAIToolsLauncherInBarExcludedFromPalette() {
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let launcher = MockAction(id: "builtin.aiTools", shouldBeEnabled: true, chrome: ActionChrome(launchesAI: true))
        let completion = MockAction(id: "builtin.completion", shouldBeEnabled: true, chrome: ActionChrome(popupBehavior: .provideCompletions))
        let normal = MockAction(id: "mock.normal", shouldBeEnabled: true)
        registry.register(builtIns: [launcher, completion, normal])

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        // The launcher is a normal bar row (bar-visible), but the palette excludes it — the AI
        // presets already cover AI there.
        XCTAssertTrue(available.contains { $0.id == "builtin.aiTools" })
        XCTAssertTrue(available.contains { $0.id == "mock.normal" })
        XCTAssertFalse(registry.searchCatalog(for: context).contains { $0.id == "builtin.aiTools" })
        XCTAssertFalse(registry.searchCatalog(for: context).contains { $0.id == "builtin.completion" })
        XCTAssertTrue(registry.searchCatalog(for: context).contains { $0.id == "mock.normal" })
    }

    @MainActor
    func testUnorderedBuiltinDefaultsIntoBuiltinGroupBeforeExtensions() {
        // Regression: with a populated `.actionOrder` that omits a newly registered builtin
        // (e.g. the AI Tools launcher on upgrade), it must slot into the builtin group — after
        // the last ordered builtin and ahead of installed extensions — not the absolute tail.
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.search", "builtin.copy", "builtin.reveal_in_finder"])
        let registry = ActionRegistry(settingsStore: store)

        let search = MockAction(id: "builtin.search", shouldBeEnabled: true)
        let copy = MockAction(id: "builtin.copy", shouldBeEnabled: true)
        let reveal = MockAction(id: "builtin.reveal_in_finder", shouldBeEnabled: true)
        let extChrome = ActionChrome(source: .extensionPkg(packageID: "com.ext.pkg"))
        let extensions = (1...4).map {
            MockAction(id: "com.ext.pkg.\($0)", shouldBeEnabled: true, chrome: extChrome)
        }
        let aiTools = MockAction(id: "builtin.aiTools", shouldBeEnabled: true, chrome: ActionChrome(launchesAI: true))

        registry.register(builtIns: [search, copy, reveal])
        registry.register(builtIns: extensions)
        registry.register(action: aiTools)

        let ids = registry.actions.map(\.id)
        let lastBuiltin = ids.firstIndex(of: "builtin.reveal_in_finder")!
        let ai = ids.firstIndex(of: "builtin.aiTools")!
        let firstExt = ids.firstIndex(of: "com.ext.pkg.1")!

        XCTAssertGreaterThan(ai, lastBuiltin, "AI Tools sits after the last ordered builtin")
        XCTAssertLessThan(ai, firstExt, "AI Tools precedes extensions by default")
    }

    // MARK: - Sub-actions follow their parent row

    private static func aiPreset(_ id: String) -> MockAction {
        MockAction(id: id, shouldBeEnabled: true,
                   chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai))
    }

    @MainActor
    private static func palette(_ registry: ActionRegistry) -> [String] {
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        return registry.searchCatalog(for: ActionContext(selection: selection, modifiers: [])).map(\.id)
    }

    /// Regression: AI presets carry chrome source `.ai` — neither user-ordered nor builtin — so
    /// they sank to the very end of the catalog however the user had dragged "AI Tools". The
    /// palette lists the presets in place of the launcher row, so dragging AI Tools to the top
    /// must put the AI commands at the top of the palette.
    @MainActor
    func testAIPresetsFollowTheLauncherOrderedFirst() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.aiTools", "builtin.copy", "builtin.search"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(builtIns: [
            MockAction(id: "builtin.copy", shouldBeEnabled: true),
            MockAction(id: "builtin.search", shouldBeEnabled: true)
        ])
        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))

        XCTAssertEqual(registry.actions.map(\.id),
                       ["builtin.aiTools", "ai.preset.proofread", "ai.preset.rewrite", "builtin.copy", "builtin.search"])
        // What the user actually sees: the palette drops the launcher, so the presets lead.
        XCTAssertEqual(Self.palette(registry),
                       ["ai.preset.proofread", "ai.preset.rewrite", "builtin.copy", "builtin.search"])
    }

    /// The same inheritance in the other direction — AI Tools dragged last keeps its presets last.
    @MainActor
    func testAIPresetsFollowTheLauncherOrderedLast() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.copy", "builtin.search", "builtin.aiTools"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(builtIns: [
            MockAction(id: "builtin.copy", shouldBeEnabled: true),
            MockAction(id: "builtin.search", shouldBeEnabled: true)
        ])

        XCTAssertEqual(registry.actions.map(\.id),
                       ["builtin.copy", "builtin.search", "builtin.aiTools", "ai.preset.proofread"])
    }

    /// With no user order at all, presets still sit with their launcher among the builtins rather
    /// than behind every installed extension.
    @MainActor
    func testAIPresetsFollowTheLauncherWithNoUserOrder() {
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let extChrome = ActionChrome(source: .extensionPkg(packageID: "com.ext.pkg"))

        registry.register(builtIns: [
            MockAction(id: "builtin.copy", shouldBeEnabled: true),
            MockLauncherAction(id: "builtin.aiTools"),
            MockAction(id: "builtin.search", shouldBeEnabled: true)
        ])
        registry.register(action: MockAction(id: "com.ext.pkg.1", shouldBeEnabled: true, chrome: extChrome))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))

        let ids = registry.actions.map(\.id)
        XCTAssertEqual(ids, [
            "builtin.copy",
            "builtin.aiTools",
            "ai.preset.proofread",
            "ai.preset.rewrite",
            "builtin.search",
            "com.ext.pkg.1"
        ])
    }

    /// Inheritance is a fallback, never an override: a child the user ordered explicitly keeps the
    /// rank they gave it.
    @MainActor
    func testExplicitlyOrderedChildKeepsItsOwnRank() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["ai.preset.rewrite", "builtin.copy", "builtin.aiTools"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: MockAction(id: "builtin.copy", shouldBeEnabled: true))

        XCTAssertEqual(registry.actions.map(\.id),
                       ["ai.preset.rewrite", "builtin.copy", "builtin.aiTools", "ai.preset.proofread"])
    }

    /// Regression (user-reported): dragging AI Tools to the top in Preferences changed nothing in
    /// the palette until OpenClip was restarted. `moveActions` published the hand-moved array
    /// directly, and a drag moves only the grabbed row — the presets kept their pre-drag position
    /// until some later registration re-sorted the catalog. The move must re-derive the order.
    @MainActor
    func testMovingTheLauncherImmediatelyMovesItsPresets() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.cut", "builtin.copy", "builtin.aiTools"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(builtIns: [
            MockAction(id: "builtin.cut", shouldBeEnabled: true),
            MockAction(id: "builtin.copy", shouldBeEnabled: true)
        ])
        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))

        XCTAssertEqual(registry.actions.map(\.id),
                       ["builtin.cut", "builtin.copy", "builtin.aiTools", "ai.preset.proofread", "ai.preset.rewrite"])

        // Drag AI Tools to the top, exactly as the Preferences outline does (indices into `actions`).
        let launcherIndex = registry.actions.firstIndex { $0.id == "builtin.aiTools" }!
        registry.moveActions(from: IndexSet(integer: launcherIndex), to: 0)

        // No re-registration, no restart: the presets follow immediately.
        XCTAssertEqual(registry.actions.map(\.id),
                       ["builtin.aiTools", "ai.preset.proofread", "ai.preset.rewrite", "builtin.cut", "builtin.copy"])
        XCTAssertEqual(Self.palette(registry),
                       ["ai.preset.proofread", "ai.preset.rewrite", "builtin.cut", "builtin.copy"])
        // The persisted order stays free of derived rows.
        XCTAssertEqual(store.get(.actionOrder), ["builtin.aiTools", "builtin.cut", "builtin.copy"])
    }

    /// Moving an ordinary row still lands exactly where it was dropped.
    @MainActor
    func testMovingAnOrdinaryActionIsAppliedImmediately() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.cut", "builtin.copy", "builtin.search"])
        let registry = ActionRegistry(settingsStore: store)
        registry.register(builtIns: [
            MockAction(id: "builtin.cut", shouldBeEnabled: true),
            MockAction(id: "builtin.copy", shouldBeEnabled: true),
            MockAction(id: "builtin.search", shouldBeEnabled: true)
        ])

        registry.moveActions(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(registry.actions.map(\.id), ["builtin.search", "builtin.cut", "builtin.copy"])
        XCTAssertEqual(store.get(.actionOrder), ["builtin.search", "builtin.cut", "builtin.copy"])
    }

    @MainActor
    func testExtensionGroupSubActionsFollowGroupAndPersistedOrderStaysFreeOfSubActions() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["com.pkg.group", "com.pkg.other"])
        let registry = ActionRegistry(settingsStore: store)
        let group = GroupAction(
            id: "com.pkg.group",
            title: "Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))
        )
        let sub1 = MockAction(id: "com.pkg.group.sub1", shouldBeEnabled: true, chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg")))
        let sub2 = MockAction(id: "com.pkg.group.sub2", shouldBeEnabled: true, chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg")))
        let other = MockAction(id: "com.pkg.other", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))

        registry.register(action: group)
        registry.register(action: sub1)
        registry.register(action: sub2)
        registry.register(action: other)

        XCTAssertEqual(registry.actions.map(\.id), ["com.pkg.group", "com.pkg.group.sub1", "com.pkg.group.sub2", "com.pkg.other"])

        // Move group after other: in actions, group is index 0. Moving group to after other (index 4)
        registry.moveActions(from: IndexSet(integer: 0), to: 4)

        // Group and its subactions move together after other
        XCTAssertEqual(registry.actions.map(\.id), ["com.pkg.other", "com.pkg.group", "com.pkg.group.sub1", "com.pkg.group.sub2"])
        // Persisted actionOrder must NOT contain sub1 or sub2!
        XCTAssertEqual(store.get(.actionOrder), ["com.pkg.other", "com.pkg.group"])
    }

    @MainActor
    func testExtensionGroupSubActionsRespectCustomMemberOrder() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let group = GroupAction(
            id: "com.pkg.group",
            title: "Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))
        )
        let sub1 = MockAction(id: "com.pkg.group.sub1", shouldBeEnabled: true, chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg")))
        let sub2 = MockAction(id: "com.pkg.group.sub2", shouldBeEnabled: true, chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg")))
        let sub3 = MockAction(id: "com.pkg.group.sub3", shouldBeEnabled: true, chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg")))

        registry.register(action: group)
        registry.register(action: sub1)
        registry.register(action: sub2)
        registry.register(action: sub3)

        XCTAssertEqual(registry.actions.map(\.id), ["com.pkg.group", "com.pkg.group.sub1", "com.pkg.group.sub2", "com.pkg.group.sub3"])

        // Reorder subactions: 3, 1, 2
        registry.setExtensionGroupMemberOrder(groupID: "com.pkg.group", memberIDs: ["com.pkg.group.sub3", "com.pkg.group.sub1", "com.pkg.group.sub2"])

        XCTAssertEqual(registry.actions.map(\.id), ["com.pkg.group", "com.pkg.group.sub3", "com.pkg.group.sub1", "com.pkg.group.sub2"])
        XCTAssertEqual(group.subActions(in: registry.actions).map(\.id), ["com.pkg.group.sub3", "com.pkg.group.sub1", "com.pkg.group.sub2"])
    }

    /// The contract `AIActionSync` leans on when the user reorders presets: `register(action:)`
    /// replaces an id *in place*, so a reorder has to unregister and re-register to move the
    /// entries — and when it does, the catalog follows the new order immediately.
    @MainActor
    func testReRegisteringPresetsInANewOrderReordersTheCatalog() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.aiTools", "builtin.cut"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: MockAction(id: "builtin.cut", shouldBeEnabled: true))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))
        XCTAssertEqual(Self.palette(registry), ["ai.preset.proofread", "ai.preset.rewrite", "builtin.cut"])

        // Re-registering in place must NOT move anything (titles/prompts changing is not a move).
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))
        XCTAssertEqual(Self.palette(registry), ["ai.preset.proofread", "ai.preset.rewrite", "builtin.cut"])

        // A real reorder: drop both, re-register in the new order.
        registry.unregister(actionID: "ai.preset.proofread")
        registry.unregister(actionID: "ai.preset.rewrite")
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        XCTAssertEqual(Self.palette(registry), ["ai.preset.rewrite", "ai.preset.proofread", "builtin.cut"])
    }

    @MainActor
    func testReplaceRegisteredActionsReordersAtomically() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["builtin.aiTools", "builtin.cut"])
        let registry = ActionRegistry(settingsStore: store)

        registry.register(action: MockLauncherAction(id: "builtin.aiTools"))
        registry.register(action: MockAction(id: "builtin.cut", shouldBeEnabled: true))
        registry.register(action: Self.aiPreset("ai.preset.proofread"))
        registry.register(action: Self.aiPreset("ai.preset.rewrite"))
        XCTAssertEqual(Self.palette(registry), ["ai.preset.proofread", "ai.preset.rewrite", "builtin.cut"])

        // Atomic replacement with reverse order
        registry.replaceRegisteredActions(
            matching: { ActionIdentity.isAIPreset($0) },
            with: [Self.aiPreset("ai.preset.rewrite"), Self.aiPreset("ai.preset.proofread")]
        )
        XCTAssertEqual(Self.palette(registry), ["ai.preset.rewrite", "ai.preset.proofread", "builtin.cut"])
    }

    /// A disabled AI preset is gone from the palette too — the toggle in AI → Actions is the same
    /// promise as the one in Preferences → Actions.
    @MainActor
    func testDisabledAIPresetIsNotOfferedInThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let enabled = MockAction(id: "ai.preset.proofread", shouldBeEnabled: true,
                                 chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai))
        // `shouldBeEnabled: false` stands in for the preset's toggle being off: the real AIAction
        // answers `isEnabled` from AIServiceManager's preset list.
        let disabled = MockAction(id: "ai.preset.rewrite", shouldBeEnabled: false,
                                  chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai))
        registry.register(builtIns: [enabled, disabled])

        XCTAssertEqual(Self.palette(registry), ["ai.preset.proofread"])
    }

    /// A disabled group takes its sub-actions with it: the palette lists the members rather than
    /// the group row, so the row's toggle has to reach them.
    @MainActor
    func testDisabledGroupHidesItsSubActionsFromThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupChrome = ActionChrome(badge: .none, rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .builtin)
        let group = MockAction(id: "mock.group", shouldBeEnabled: true, chrome: groupChrome)
        let member = MockAction(id: "mock.group.member", shouldBeEnabled: true)
        let other = MockAction(id: "mock.other", shouldBeEnabled: true)
        registry.register(builtIns: [group, member, other])
        XCTAssertEqual(Self.palette(registry), ["mock.group", "mock.group.member", "mock.other"])

        store.set(.disabledActionIDs, value: Set(["mock.group"]))
        XCTAssertEqual(Self.palette(registry), ["mock.other"])
    }

    /// A disabled extension package hides its actions from the palette as well as the bar.
    @MainActor
    func testDisabledPackageIsNotOfferedInThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let extChrome = ActionChrome(source: .extensionPkg(packageID: "com.ext.pkg"))
        registry.register(builtIns: [
            MockAction(id: "com.ext.pkg.action", shouldBeEnabled: true, chrome: extChrome),
            MockAction(id: "mock.other", shouldBeEnabled: true)
        ])
        // The builtin leads: an un-ordered extension sorts behind it.
        XCTAssertEqual(Self.palette(registry), ["mock.other", "com.ext.pkg.action"])

        store.set(.disabledPackages, value: Set(["com.ext.pkg"]))
        XCTAssertEqual(Self.palette(registry), ["mock.other"])
    }

    @MainActor
    func testUnorderedBuiltinActionsPreserveStableInsertionOrder() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)

        let b1 = MockAction(id: "builtin.1", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b2 = MockAction(id: "builtin.2", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b3 = MockAction(id: "builtin.3", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b4 = MockAction(id: "builtin.4", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))

        registry.register(action: b1)
        registry.register(action: b2)
        registry.register(action: b3)
        registry.register(action: b4)

        XCTAssertEqual(registry.actions.map(\.id), ["builtin.1", "builtin.2", "builtin.3", "builtin.4"])
    }

    @MainActor
    func testDuplicateActionOrderIDsDoNotTrapAndKeepFirstRank() {
        let store = MemorySettingsStore()
        store.set(.actionOrder, value: ["action.b", "action.a", "action.b"])
        let registry = ActionRegistry(settingsStore: store)

        let a = MockAction(id: "action.a", shouldBeEnabled: true)
        let b = MockAction(id: "action.b", shouldBeEnabled: true)

        registry.register(action: a)
        registry.register(action: b)

        XCTAssertEqual(registry.actions.map(\.id), ["action.b", "action.a"])
    }

    @MainActor
    func testClipboardFallbackExcludesRequiresLiveSelectionActions() {
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let copy = MockAction(id: "builtin.copy", shouldBeEnabled: true, chrome: ActionChrome(requiresLiveSelection: true))
        let cut = MockAction(id: "builtin.cut", shouldBeEnabled: true, chrome: ActionChrome(requiresLiveSelection: true))
        let paste = MockAction(id: "builtin.paste", shouldBeEnabled: true)
        let search = MockAction(id: "builtin.search", shouldBeEnabled: true)
        registry.register(builtIns: [copy, cut, paste, search])

        let app = AppIdentity(bundleIdentifier: "com.test", localizedName: "Test")
        let fallbackSelection = SelectionContext(text: "hello", sourceApp: app, cursorPosition: .zero, timestamp: Date(), appPolicy: .default, isClipboardFallback: true)
        let available = registry.availableActions(for: ActionContext(selection: fallbackSelection, modifiers: []))

        XCTAssertFalse(available.contains { $0.id == "builtin.copy" })
        XCTAssertFalse(available.contains { $0.id == "builtin.cut" })
        XCTAssertTrue(available.contains { $0.id == "builtin.paste" })
        XCTAssertTrue(available.contains { $0.id == "builtin.search" })

        // Same text, real selection (no fallback flag): Copy/Cut come back.
        let normalSelection = SelectionContext(text: "hello", sourceApp: app, cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let normal = registry.availableActions(for: ActionContext(selection: normalSelection, modifiers: []))
        XCTAssertTrue(normal.contains { $0.id == "builtin.copy" })
        XCTAssertTrue(normal.contains { $0.id == "builtin.cut" })
    }

    @MainActor
    func testCopyAndCutBuiltinsRequireLiveSelection() {
        let builtins = BuiltinRegistry.makeCoreBuiltins()
        XCTAssertTrue(builtins.first { $0.id == "builtin.copy" }?.chrome.requiresLiveSelection == true)
        XCTAssertTrue(builtins.first { $0.id == "builtin.cut" }?.chrome.requiresLiveSelection == true)
        XCTAssertTrue(builtins.first { $0.id == "builtin.paste" }?.chrome.requiresLiveSelection == false)
        XCTAssertTrue(builtins.first { $0.id == "builtin.search" }?.chrome.requiresLiveSelection == false)
    }

    func testMemorySettingsStorePublisherReentrancyDoesNotDeadlock() {
        let store = MemorySettingsStore()
        let key = SettingKey<Set<String>>("test.reentrancy.key", defaultValue: [])
        var received: Set<String>? = nil
        let cancellable = store.publisher(for: key).sink { val in
            received = store.get(key)
        }
        
        store.set(key, value: Set(["item1"]))
        XCTAssertEqual(received, Set(["item1"]))
        _ = cancellable
    }
}

