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

    /// The context menu's Delete item appears only for what can actually be removed: custom
    /// actions, installed extensions, and groups. Built-ins and AI presets never qualify.
    func testCanDeleteClassifiesActionSources() {
        let custom = CustomAction(id: "custom.a", title: "A", iconName: "star", type: .openURL(urlTemplate: "https://example.com"))
        XCTAssertTrue(ActionDeletion.canDelete(custom))

        let extensionAction = URLTemplateAction(id: "com.example.ext", title: "Ext", icon: .symbol("link"), urlTemplate: "https://example.com")
        XCTAssertTrue(ActionDeletion.canDelete(extensionAction))

        XCTAssertFalse(ActionDeletion.canDelete(CopyAction()))

        let group = CustomAction(
            id: "custom.group",
            title: "Group",
            iconName: "folder",
            type: .textSnippet(template: ""),
            chrome: ActionChrome(badge: .none, rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .custom)
        )
        XCTAssertTrue(ActionDeletion.canDelete(group))
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

        let duplicateAction = try XCTUnwrap(manager.loadedActions.first(where: { $0.id == duplicatedActionID }))
        XCTAssertTrue(duplicateAction.title.contains("Copy"))

        // The copy's id must be namespaced under its new package identifier. Otherwise
        // `uninstallExtension`, which matches a package by id prefix, can never find it.
        let duplicatePackageID = try XCTUnwrap(ActionIdentity.extensionPackageID(of: duplicateAction))
        XCTAssertNotEqual(duplicatePackageID, "com.example.hello")
        XCTAssertTrue(
            duplicatedActionID.hasPrefix(duplicatePackageID + "."),
            "duplicated action id \(duplicatedActionID) must be namespaced under \(duplicatePackageID)"
        )

        try await manager.uninstallExtension(actionID: duplicatePackageID, targetDir: tempExtensionsDir)
        let remainingPackageIDs = Set(manager.loadedActions.compactMap { ActionIdentity.extensionPackageID(of: $0) })
        XCTAssertFalse(
            remainingPackageIDs.contains(duplicatePackageID),
            "uninstall must remove every action of the duplicated package"
        )
        XCTAssertTrue(remainingPackageIDs.contains("com.example.hello"))
        XCTAssertEqual(manager.loadedActions.count, 1)
    }

    /// Regression: a package duplicated before ids were namespaced carries an action id with no
    /// package prefix. Uninstall must still find it by its declared action id, or it is stranded.
    func testUninstallMatchesLegacyUnprefixedActionID() async throws {
        let packageDir = tempExtensionsDir.appendingPathComponent("com.example.legacy")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let manifest = ExtensionMetadata(
            identifier: "com.example.legacy",
            name: "Legacy",
            actions: [ExtensionActionMetadata(id: "evaluate.copy.abc123", title: "Legacy", icon: "star", url: "https://example.com", type: "url")]
        )
        try ExtensionManifestStore.writeManifest(manifest, to: packageDir.appendingPathComponent(Constants.manifestFileName))

        let manager = ExtensionManager.shared
        manager.settingsStore = settingsStore
        manager.actionFactory = DefaultActionFactory(optionStore: SecretActionOptionStore())
        await manager.loadExtensions(from: tempExtensionsDir)
        let legacyID = try XCTUnwrap(manager.loadedActions.first?.id)
        XCTAssertEqual(legacyID, "evaluate.copy.abc123")

        try await manager.uninstallExtension(actionID: legacyID, targetDir: tempExtensionsDir)
        XCTAssertTrue(manager.loadedActions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.path))
    }
}
