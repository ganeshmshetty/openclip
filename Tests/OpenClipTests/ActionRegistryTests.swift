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
    func testDenyFormattingPolicyFiltersFormattingActions() {
        let registry = ActionRegistry.shared
        
        struct MockFormattingAction: Action {
            let id = "mock.formatting"
            let title = "Format"
            let icon = ActionIcon.symbol("star")
            var isFormatting: Bool { true }
            
            @MainActor
            func isEnabled(for context: ActionContext) -> Bool { return true }
            @MainActor
            func perform(_ context: ActionContext) async throws -> ActionResult { return .success }
        }
        
        let formatAction = MockFormattingAction()
        registry.register(action: formatAction)
        
        let denyPolicy = AppPolicyContext(denyFormatting: true, denyProbe: false, denyPreprobe: false, grabPasteboard: false, assumePaste: false)
        let denySelection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: denyPolicy)
        let denyContext = ActionContext(selection: denySelection, modifiers: [])
        
        let availableWithDeny = registry.availableActions(for: denyContext)
        XCTAssertFalse(availableWithDeny.contains(where: { $0.id == "mock.formatting" }), "Formatting action should be filtered out when denyFormatting is true")
        
        let allowSelection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let allowContext = ActionContext(selection: allowSelection, modifiers: [])
        
        let availableWithAllow = registry.availableActions(for: allowContext)
        XCTAssertTrue(availableWithAllow.contains(where: { $0.id == "mock.formatting" }), "Formatting action should be included when denyFormatting is false")
    }
    
    @MainActor
    func testDisabledActionsAreFiltered() {
        let registry = ActionRegistry.shared
        
        let action = MockAction(id: "mock.disabled.test", shouldBeEnabled: true)
        registry.register(action: action)
        
        let oldDisabled = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey)
        UserDefaults.standard.set(["mock.disabled.test"], forKey: Constants.disabledActionIDsKey)
        defer {
            if let oldDisabled {
                UserDefaults.standard.set(oldDisabled, forKey: Constants.disabledActionIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.disabledActionIDsKey)
            }
        }
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == "mock.disabled.test" }))
    }
    
    @MainActor
    func testDisabledPackageHidesAllPackageActions() {
        let registry = ActionRegistry.shared
        
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
        
        let oldDisabled = UserDefaults.standard.stringArray(forKey: "disabledPackages")
        UserDefaults.standard.set([packageID], forKey: "disabledPackages")
        defer {
            if let oldDisabled {
                UserDefaults.standard.set(oldDisabled, forKey: "disabledPackages")
            } else {
                UserDefaults.standard.removeObject(forKey: "disabledPackages")
            }
        }
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == a1.id }))
        XCTAssertFalse(available.contains(where: { $0.id == a2.id }))
    }

    @MainActor
    func testDisabledGroupRowHidesItsSubActions() {
        let registry = ActionRegistry.shared
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

        let oldDisabled = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey)
        UserDefaults.standard.set([groupID], forKey: Constants.disabledActionIDsKey)
        defer {
            if let oldDisabled {
                UserDefaults.standard.set(oldDisabled, forKey: Constants.disabledActionIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.disabledActionIDsKey)
            }
        }

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        XCTAssertFalse(available.contains { $0.id == groupID })
        XCTAssertFalse(available.contains { $0.id == subA.id })
        XCTAssertFalse(available.contains { $0.id == subB.id })
    }

    @MainActor
    func testEnabledGroupRowKeepsSubActionsAvailable() {
        let registry = ActionRegistry.shared
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

        let oldDisabled = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey)
        UserDefaults.standard.removeObject(forKey: Constants.disabledActionIDsKey)
        defer {
            if let oldDisabled {
                UserDefaults.standard.set(oldDisabled, forKey: Constants.disabledActionIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.disabledActionIDsKey)
            }
        }

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        XCTAssertTrue(available.contains { $0.id == groupID })
        XCTAssertTrue(available.contains { $0.id == sub.id })
    }

    @MainActor
    func testSearchCatalogIncludesAllAndExcludesOnlyCompletion() {
        let registry = ActionRegistry()
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: "mock.searchgroup", shouldBeEnabled: true, chrome: groupChrome)
        let sub = MockAction(id: "mock.searchgroup.a", shouldBeEnabled: true)
        let completion = MockAction(id: "builtin.completion", shouldBeEnabled: true)
        let disabled = MockAction(id: "mock.searchdisabled", shouldBeEnabled: false)
        let normal = MockAction(id: "mock.searchnormal", shouldBeEnabled: true)
        registry.register(builtIns: [group, sub, completion, disabled, normal])

        let catalog = registry.searchCatalog

        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup" })
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup.a" })
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchdisabled" })
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchnormal" })
        XCTAssertFalse(catalog.contains { $0.id == "builtin.completion" })
    }

    @MainActor
    func testAIChromeActionsExcludedFromBarButIncludedInSearchCatalog() {
        let registry = ActionRegistry()
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
        XCTAssertTrue(registry.searchCatalog.contains { $0.id == "ai.preset.proofread" })
    }

    @MainActor
    func testAIToolsLauncherInBarExcludedFromPalette() {
        let registry = ActionRegistry()
        let launcher = MockAction(id: "builtin.aiTools", shouldBeEnabled: true, chrome: ActionChrome(launchesAI: true))
        let completion = MockAction(id: "builtin.completion", shouldBeEnabled: true)
        let normal = MockAction(id: "mock.normal", shouldBeEnabled: true)
        registry.register(builtIns: [launcher, completion, normal])

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)

        // The launcher is a normal bar row (bar-visible), but the palette excludes it — the AI
        // presets already cover AI there.
        XCTAssertTrue(available.contains { $0.id == "builtin.aiTools" })
        XCTAssertTrue(available.contains { $0.id == "mock.normal" })
        XCTAssertFalse(registry.searchCatalog.contains { $0.id == "builtin.aiTools" })
        XCTAssertFalse(registry.searchCatalog.contains { $0.id == "builtin.completion" })
        XCTAssertTrue(registry.searchCatalog.contains { $0.id == "mock.normal" })
    }

    @MainActor
    func testUnorderedBuiltinDefaultsIntoBuiltinGroupBeforeExtensions() {
        // Regression: with a populated `.actionOrder` that omits a newly registered builtin
        // (e.g. the AI Tools launcher on upgrade), it must slot into the builtin group — after
        // the last ordered builtin and ahead of installed extensions — not the absolute tail.
        let userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        let store = DefaultSettingsStore(userDefaults: userDefaults)
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

    @MainActor
    func testClipboardFallbackExcludesRequiresLiveSelectionActions() {
        let registry = ActionRegistry()
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
}
