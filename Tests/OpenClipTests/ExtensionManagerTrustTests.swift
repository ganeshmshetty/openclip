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

        // A second new package after migration is silently gated.
        try writePackage(packageID: "com.t.gate2", name: "Gate2")
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 2)
        let gated = try XCTUnwrap(manager.loadedActions.first { $0 is GatedExtensionAction } as? GatedExtensionAction)
        XCTAssertEqual(gated.packageID, "com.t.gate2")
        XCTAssertEqual(gated.reason, .notEnabled)
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testEnableThenTamperFlow() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.tf", name: "TF")
        manager.prepareInstall(source: "package", packageID: "com.t.tf")

        var events: [ExtensionTrustChange] = []
        manager.onTrustChange = { events.append($0) }

        await manager.loadExtensions(from: tempDir) // migration → trusted
        let hash = store.get(.extensionTrustHashes)["com.t.tf"]
        XCTAssertNotNil(hash)

        // Tamper: edit the script, reload → gated + trust seen (silent, no events).
        try writePackage(packageID: "com.t.tf", name: "TF", script: "echo edited")
        await manager.loadExtensions(from: tempDir)
        let gated = try XCTUnwrap(manager.loadedActions.first as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.tf"], "seen")
        XCTAssertTrue(events.isEmpty)

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
    func testDeveloperLiveHotReloadAutoRehashes() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.dev", name: "Dev")
        manager.prepareInstall(source: "developer", packageID: "com.t.dev")

        var events: [ExtensionTrustChange] = []
        manager.onTrustChange = { events.append($0) }

        await manager.loadExtensions(from: tempDir) // migration → trusted
        let initialHash = store.get(.extensionTrustHashes)["com.t.dev"]
        XCTAssertNotNil(initialHash)

        // Edit the script: developer extension seamlessly auto-rehashes and stays runnable!
        try writePackage(packageID: "com.t.dev", name: "Dev", script: "echo updated")
        await manager.loadExtensions(from: tempDir)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.dev"], "trusted")
        let updatedHash = store.get(.extensionTrustHashes)["com.t.dev"]
        XCTAssertNotEqual(initialHash, updatedHash)
        XCTAssertTrue(events.isEmpty)
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
    func testStandaloneScriptWithDeclaredIdentifierStaysEnabled() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        manager.actionFactory = DefaultActionFactory()
        defer { manager.actionFactory = nil }

        // A standalone script declaring `// identifier:` derives its package id from the header,
        // not the filename, so packageHash(forPackageID:) must resolve the declared identifier.
        let scriptURL = tempDir.appendingPathComponent("myid.sh")
        try """
        // identifier: com.myid
        // Title: My ID Script
        #!/bin/sh
        echo hi
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        var events: [ExtensionTrustChange] = []
        manager.onTrustChange = { events.append($0) }

        // First load = migration: auto-trusts with the gate-computed hash.
        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 1)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
        XCTAssertEqual(store.get(.extensionTrust)["com.myid"], "trusted")

        // Re-enable through the trust model — this records the hash via
        // packageHash(forPackageID:), which must resolve the declared identifier (I3).
        await manager.enablePackage(packageID: "com.myid", in: tempDir)
        XCTAssertEqual(store.get(.extensionTrustHashes)["com.myid"]?.count, 64)

        // Reload after enable must not flip the package to tampered.
        await manager.loadExtensions(from: tempDir)
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testEnablePackageFailsClosedWhenFingerprintUnresolvable() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.enil", name: "ENil")
        store.set(.extensionTrust, value: ["com.t.enil": "seen"])

        // Break the manifest so no fingerprint can resolve; enablePackage must persist nothing.
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("ENil.openclipext").appendingPathComponent("openclip.json"))
        await manager.enablePackage(packageID: "com.t.enil", in: tempDir)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.enil"], "seen", "trust must not be persisted without a fingerprint")
        XCTAssertNil(store.get(.extensionTrustHashes)["com.t.enil"], "no hash may be recorded")
    }

    @MainActor
    func testRetrustAfterAuthorizedEditPreservesRevokedAndSeenStates() async throws {
        let store = MemorySettingsStore()
        let manager = ExtensionManager.shared
        manager.settingsStore = store
        try writePackage(packageID: "com.t.edit", name: "Edit")
        manager.prepareInstall(source: "package", packageID: "com.t.edit")
        await manager.loadExtensions(from: tempDir) // migration → trusted

        // Trusted + authorized edit → re-trusted with a fresh fingerprint (the normal flow).
        try writePackage(packageID: "com.t.edit", name: "Edit", script: "echo edited")
        await manager.retrustAfterAuthorizedEdit(packageID: "com.t.edit", in: tempDir)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.edit"], "trusted")
        XCTAssertFalse(manager.loadedActions[0] is GatedExtensionAction)

        // Revoked + edit → stays revoked: a config-sheet save must not re-enable the package.
        await manager.disablePackage(packageID: "com.t.edit", in: tempDir)
        try writePackage(packageID: "com.t.edit", name: "Edit", script: "echo edited-again")
        await manager.retrustAfterAuthorizedEdit(packageID: "com.t.edit", in: tempDir)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.edit"], "revoked")
        let revoked = try XCTUnwrap(manager.loadedActions.first as? GatedExtensionAction)
        XCTAssertEqual(revoked.reason, .revoked)

        // Seen (never enabled) + edit → stays seen: an edit save is not consent.
        store.set(.extensionTrust, value: ["com.t.edit": "seen"])
        await manager.retrustAfterAuthorizedEdit(packageID: "com.t.edit", in: tempDir)
        XCTAssertEqual(store.get(.extensionTrust)["com.t.edit"], "seen")
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