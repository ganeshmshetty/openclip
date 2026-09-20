import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionDuplicationTests: XCTestCase {
    private var tempDir: URL!
    private var tempExtensionsDir: URL!
    private var settingsStore: MemorySettingsStore!
    private var coordinator: ActionCoordinator!
    private var registry: ActionRegistry!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ActionDuplicationTests-\(UUID().uuidString)")
        tempExtensionsDir = tempDir.appendingPathComponent("extensions")
        try FileManager.default.createDirectory(at: tempExtensionsDir, withIntermediateDirectories: true)

        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
    }

    override func tearDown() async throws {
        await MainActor.run { TestIsolation.reset() }
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testDuplicateCustomAction() {
        let original = CustomAction(
            id: "custom.test1",
            title: "My Search",
            iconName: "magnifyingglass",
            type: .openURL(urlTemplate: "https://example.com/?q={text}")
        )
        coordinator.saveCustomAction(original)
        XCTAssertEqual(coordinator.customActions.count, 1)

        let duplicate = coordinator.duplicateCustomAction(actionID: original.id)
        XCTAssertNotNil(duplicate)
        XCTAssertNotEqual(duplicate?.id, original.id)
        XCTAssertEqual(duplicate?.title, "My Search Copy")
        XCTAssertEqual(duplicate?.iconName, "magnifyingglass")
        XCTAssertEqual(duplicate?.type, original.type)
        XCTAssertEqual(coordinator.customActions.count, 2)

        let order = settingsStore.get(.actionOrder)
        XCTAssertEqual(order, [original.id, duplicate!.id])
    }

    func testDeleteCustomActionRemovesActionAndCleansState() {
        let customAction = CustomAction(
            id: "custom.delete_test",
            title: "Delete Me",
            iconName: "trash",
            type: .textSnippet(template: "snippet")
        )

        coordinator.saveCustomAction(customAction)
        XCTAssertTrue(coordinator.customActions.contains(where: { $0.id == "custom.delete_test" }))
        XCTAssertTrue(coordinator.actions.contains(where: { $0.id == "custom.delete_test" }))

        _ = ActionBindingStore.shared.setAlias("del", for: "custom.delete_test")
        XCTAssertEqual(ActionBindingStore.shared.alias(for: "custom.delete_test"), "del")

        ActionCustomizationManager.shared.setOverride(for: "custom.delete_test", title: "Customized", symbol: nil, text: nil)
        XCTAssertEqual(ActionCustomizationManager.shared.override(for: "custom.delete_test")?.customTitle, "Customized")

        coordinator.deleteCustomAction(actionID: "custom.delete_test")

        XCTAssertFalse(coordinator.customActions.contains(where: { $0.id == "custom.delete_test" }))
        XCTAssertFalse(coordinator.actions.contains(where: { $0.id == "custom.delete_test" }))
        XCTAssertNil(ActionBindingStore.shared.alias(for: "custom.delete_test"))
        XCTAssertNil(ActionCustomizationManager.shared.override(for: "custom.delete_test"))

        coordinator.loadCustomActions()
        XCTAssertFalse(coordinator.customActions.contains(where: { $0.id == "custom.delete_test" }))
    }

    func testDeleteCustomActionWhenEmptyPersistsEmptyList() {
        let action1 = CustomAction(id: "custom.only_one", title: "Solo", iconName: "star", type: .openURL(urlTemplate: "https://example.com"))
        coordinator.saveCustomAction(action1)
        XCTAssertEqual(coordinator.customActions.count, 1)

        coordinator.deleteCustomAction(actionID: "custom.only_one")
        XCTAssertTrue(coordinator.customActions.isEmpty)

        coordinator.loadCustomActions()
        XCTAssertTrue(coordinator.customActions.isEmpty)
    }

    func testDuplicateExtensionPackage() async throws {
        let packageDir = tempExtensionsDir.appendingPathComponent("com.example.hello")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let originalMeta = ExtensionActionMetadata(
            id: "say-hello",
            title: "Say Hello",
            icon: "hand.wave",
            url: "https://example.com/hello",
            type: "url"
        )
        let originalManifest = ExtensionMetadata(
            identifier: "com.example.hello",
            name: "Hello Extension",
            actions: [originalMeta]
        )
        let manifestURL = packageDir.appendingPathComponent(Constants.manifestFileName)
        try ExtensionManifestStore.writeManifest(originalManifest, to: manifestURL)

        let manager = ExtensionManager.shared
        manager.settingsStore = settingsStore
        manager.actionFactory = DefaultActionFactory(optionStore: SecretActionOptionStore())
        await manager.loadExtensions(from: tempExtensionsDir)
        XCTAssertEqual(manager.loadedActions.count, 1)
        let originalActionID = manager.loadedActions[0].id

        let duplicatedActionID = try await manager.duplicateExtension(actionID: originalActionID, targetDir: tempExtensionsDir)
        XCTAssertFalse(duplicatedActionID.isEmpty)
        XCTAssertNotEqual(duplicatedActionID, originalActionID)
        XCTAssertEqual(manager.loadedActions.count, 2)

        let duplicateAction = manager.loadedActions.first(where: { $0.id == duplicatedActionID })
        XCTAssertNotNil(duplicateAction)
        XCTAssertTrue(duplicateAction?.title.contains("Copy") ?? false)
    }
}
