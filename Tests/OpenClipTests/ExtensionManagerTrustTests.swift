import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManagerTrustTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    private func writePackage(packageID: String, name: String, script: String = "echo hi") throws {
        let pkg = tempDir.appendingPathComponent("\(name).openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try """
        {"identifier":"\(packageID)","name":"\(name)","actions":[
            {"title":"Run","type":"shell","script":"main.sh"}]}
        """.write(to: pkg.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        try script.write(to: pkg.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testConfiguredManagerGatesNewLocalPackage() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.gate", name: "Gate")

        var events: [ExtensionTrustChange] = []
        manager.onTrustChange = { events.append($0) }

        // First load = migration: the package auto-trusts.
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 1)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
        XCTAssertEqual(store.get(.extensionTrustMigrated), true)
        XCTAssertTrue(events.isEmpty)

        // A second new package after migration is gated + notifies.
        try writePackage(packageID: "com.t.gate2", name: "Gate2")
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 2)
        let gated = try XCTUnwrap(manager.loadedActions.first { $0 is GatedExtensionAction } as? GatedExtensionAction)
        XCTAssertEqual(gated.packageID, "com.t.gate2")
        XCTAssertEqual(gated.reason, .notEnabled)
        XCTAssertEqual(events, [.newPackage(packageID: "com.t.gate2", name: "Gate2")])
    }

    @MainActor
    func testEnableThenTamperFlow() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.tf", name: "TF")

        var events: [ExtensionTrustChange] = []
        manager.onTrustChange = { events.append($0) }

        await manager.loadExtensions(from: tempDir) // migration → trusted
        let hash = store.get(.extensionTrustHashes)["com.t.tf"]
        XCTAssertNotNil(hash)

        // Tamper: edit the script, reload → gated + tampered event + trust seen.
        try writePackage(packageID: "com.t.tf", name: "TF", script: "echo edited")
        await manager.loadExtensions(from: tempDir)
        let gated = try XCTUnwrap(manager.loadedActions.first as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.tf"], "seen")
        XCTAssertEqual(events, [.tampered(packageID: "com.t.tf", name: "TF")])

        // Re-enable through the trust-model API → trusted + hash recorded + real actions back.
        await manager.enablePackage(packageID: "com.t.tf", in: tempDir)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.tf"], "trusted")
        XCTAssertEqual(store.get(.extensionTrustHashes)["com.t.tf"]?.count, 64)

        // Disable → revoked, gated again.
        await manager.disablePackage(packageID: "com.t.tf", in: tempDir)
        let revoked = try XCTUnwrap(manager.loadedActions.first as? GatedExtensionAction)
        XCTAssertEqual(revoked.reason, .revoked)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.tf"], "revoked")
    }

    @MainActor
    func testPrepareInstallMarksStoreSourceAndAutoTrusts() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.prep", name: "Prep")

        manager.prepareInstall(source: "store", packageID: "com.t.prep")
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(store.get(.extensionSources)["com.t.prep"], "store")
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction, "store installs auto-trust")
        XCTAssertEqual(store.get(.extensionTrust)["com.t.prep"], "trusted")
    }

    @MainActor
    func testUnconfiguredManagerSkipsGatingEntirely() async throws {
        // settingsStore nil → raw behavior, existing tests stay green.
        let manager = ExtensionManager.shared
        manager.settingsStore = nil
        try writePackage(packageID: "com.t.raw", name: "Raw")
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 1)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
    }
}