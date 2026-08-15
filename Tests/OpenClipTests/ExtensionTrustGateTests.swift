import XCTest
@testable import Core

final class ExtensionTrustGateTests: XCTestCase {
    var tempDir: URL!
    var store: MemorySettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = MemorySettingsStore()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // Writes a single-action manifest package and returns its scanned actions (no gate).
    @MainActor
    private func scannedActions(for packageID: String, name: String, script: String = "echo hi", openClipVersion: String? = nil) async -> [any Action] {
        let pkg = tempDir.appendingPathComponent("\(name).openclipext")
        try! FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let versionField = openClipVersion.map { ",\"openClipVersion\":\"\($0)\"" } ?? ""
        try! """
        {"identifier":"\(packageID)","name":"\(name)"\(versionField),"actions":[
            {"title":"Run","type":"shell","script":"main.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try! script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return await ExtensionManager.scanActionsForTest(in: tempDir)
    }

    @MainActor
    private func plan(packageID: String, name: String, trust: [String: String], hashes: [String: String], sources: [String: String], isMigrated: Bool, script: String = "echo hi", appVersion: String = "1.4.0", openClipVersion: String? = nil) async throws -> ExtensionGatePlan {
        let actions = await scannedActions(for: packageID, name: name, script: script, openClipVersion: openClipVersion)
        return ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: trust, hashes: hashes, sources: sources,
            isMigrated: isMigrated, appVersion: appVersion
        )
    }

    @MainActor
    func testNewLocalPackageBeforeMigrationAutoTrusts() async throws {
        let p = try await plan(packageID: "com.t.first", name: "First", trust: [:], hashes: [:], sources: [:], isMigrated: false)
        XCTAssertEqual(p.actions.count, 1)
        XCTAssertFalse(p.actions[0] is GatedExtensionAction, "migration must keep the real action")
        XCTAssertEqual(p.trust["com.t.first"], "trusted")
        XCTAssertEqual(p.hashes["com.t.first"]?.count, 64)
        XCTAssertTrue(p.trustChanged)
        XCTAssertTrue(p.hashesChanged)
        XCTAssertTrue(p.migratedChanged, "migration flag must be set once")
        XCTAssertTrue(p.isMigrated)
        XCTAssertTrue(p.events.isEmpty)
    }

    @MainActor
    func testNewLocalPackageAfterMigrationIsGatedAndNotifies() async throws {
        let p = try await plan(packageID: "com.t.new", name: "New", trust: [:], hashes: [:], sources: [:], isMigrated: true)
        XCTAssertEqual(p.actions.count, 1)
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .notEnabled)
        XCTAssertEqual(p.trust["com.t.new"], "seen")
        XCTAssertEqual(p.events, [.newPackage(packageID: "com.t.new", name: "New")])
    }

    @MainActor
func testTrustedPackageWithMatchingHashRuns() async throws {
        let first = try await plan(packageID: "com.t.t", name: "T", trust: [:], hashes: [:], sources: [:], isMigrated: false)
        let hash = first.hashes["com.t.t"] ?? "missing"
        let p = try await plan(packageID: "com.t.t", name: "T", trust: ["com.t.t": "trusted"], hashes: ["com.t.t": hash], sources: [:], isMigrated: true)
        XCTAssertFalse(p.actions[0] is GatedExtensionAction)
        XCTAssertTrue(p.events.isEmpty)
    }

    @MainActor
func testChangedTrustedPackageFlipsToGatedAndNotifies() async throws {
        let first = try await plan(packageID: "com.t.tam", name: "Tam", trust: [:], hashes: [:], sources: [:], isMigrated: false)
        let hash = first.hashes["com.t.tam"] ?? "missing"
        let p = try await plan(packageID: "com.t.tam", name: "Tam", trust: ["com.t.tam": "trusted"], hashes: ["com.t.tam": hash], sources: [:], isMigrated: true, script: "echo edited")
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(p.trust["com.t.tam"], "seen")
        XCTAssertEqual(p.events, [.tampered(packageID: "com.t.tam", name: "Tam")])
    }

    @MainActor
    func testStorePackageDriftIsTamperedLikeLocal() async throws {
        // Fresh store install (no record) → auto-trusted, no event.
        let p = try await plan(packageID: "com.t.store", name: "Store", trust: [:], hashes: [:], sources: ["com.t.store": "store"], isMigrated: true)
        XCTAssertFalse(p.actions[0] is GatedExtensionAction)
        XCTAssertEqual(p.trust["com.t.store"], "trusted")
        XCTAssertTrue(p.events.isEmpty)

        // Drifted store package (stale hash) → seen + tampered + gated .filesChanged,
        // exactly like a local package. Only the update flow re-trusts.
        let hash = p.hashes["com.t.store"]!
        let p2 = try await plan(packageID: "com.t.store", name: "Store", trust: ["com.t.store": "trusted"], hashes: ["com.t.store": hash], sources: ["com.t.store": "store"], isMigrated: true, script: "echo updated")
        let gated = try XCTUnwrap(p2.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(p2.trust["com.t.store"], "seen")
        XCTAssertEqual(p2.events, [.tampered(packageID: "com.t.store", name: "Store")])
    }

    @MainActor
    func testFreshStoreInstallAutoTrustsEvenWhenMigrated() async throws {
        // C1+I1 combination: a fresh store install (record == nil) auto-trusts even after the
        // migration flag is set — the fresh-store branch must not consult migration.
        let p = try await plan(packageID: "com.t.fresh", name: "Fresh", trust: [:], hashes: [:], sources: ["com.t.fresh": "store"], isMigrated: true)
        XCTAssertFalse(p.actions[0] is GatedExtensionAction)
        XCTAssertEqual(p.trust["com.t.fresh"], "trusted")
        XCTAssertTrue(p.events.isEmpty)
    }

    @MainActor
    func testFreshStoreInstallFailsClosedWhenFingerprintUnresolvable() async throws {
        // Scan a valid package, then delete it so fingerprinting returns nil at evaluate time.
        // A fresh store install must not auto-trust or run without a hash.
        let actions = await scannedActions(for: "com.t.nilhash", name: "NilHash")
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("NilHash.openclipext"))

        let p = ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: [:], hashes: [:], sources: ["com.t.nilhash": "store"],
            isMigrated: true, appVersion: "1.4.0"
        )
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertNil(p.trust["com.t.nilhash"], "must not persist trust without a fingerprint")
        XCTAssertTrue(p.hashes.isEmpty, "must not persist an empty hash")
        XCTAssertFalse(p.trustChanged)
        XCTAssertFalse(p.hashesChanged)
    }

    @MainActor
    func testTrustedPackageFailsClosedWhenFingerprintUnresolvable() async throws {
        let actions = await scannedActions(for: "com.t.niltrust", name: "NilTrust")
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("NilTrust.openclipext"))

        let p = ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: ["com.t.niltrust": "trusted"], hashes: ["com.t.niltrust": "oldhash"],
            sources: [:], isMigrated: true, appVersion: "1.4.0"
        )
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(p.trust["com.t.niltrust"], "seen", "unverifiable trusted package flips to seen")
        XCTAssertEqual(p.events, [.tampered(packageID: "com.t.niltrust", name: "NilTrust")])
        XCTAssertEqual(p.hashes["com.t.niltrust"], "oldhash", "the stale hash must be left untouched, not replaced by an empty one")
    }

    @MainActor
    func testStorePackageThatIsRevokedStaysRevoked() async throws {
        let p = try await plan(packageID: "com.t.srev", name: "SRev", trust: ["com.t.srev": "revoked"], hashes: [:], sources: ["com.t.srev": "store"], isMigrated: true)
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .revoked)
        XCTAssertEqual(p.trust["com.t.srev"], "revoked", "revoked must survive an update")
    }

    @MainActor
    func testRevokedLocalPackageStaysGated() async throws {
        let p = try await plan(packageID: "com.t.rev", name: "Rev", trust: ["com.t.rev": "revoked"], hashes: [:], sources: [:], isMigrated: true)
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .revoked)
    }

    @MainActor
    func testOpenClipVersionGatesIncompatibleTrustedPackage() async throws {
        // Trusted + matching hash, but the package requires a newer app → gate on needsNewerApp,
        // NOT tampered (version check runs after trust resolution).
        let first = try await plan(packageID: "com.t.minv", name: "MinV", trust: [:], hashes: [:], sources: [:], isMigrated: false, openClipVersion: "2.0.0")
        let hash = first.hashes["com.t.minv"]!
        let p = try await plan(packageID: "com.t.minv", name: "MinV", trust: ["com.t.minv": "trusted"], hashes: ["com.t.minv": hash], sources: [:], isMigrated: true, appVersion: "1.4.0", openClipVersion: "2.0.0")
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .needsNewerApp(required: "2.0.0"))
        XCTAssertEqual(p.trust["com.t.minv"], "trusted", "a matching-hash trusted package must gate on needsNewerApp, not filesChanged")
        XCTAssertTrue(p.events.isEmpty, "version gating is not a tamper event")
    }

    @MainActor
    func testNeedsNewerAppForTrustedPackage() async throws {
        // Same trusted + matching-hash package: a satisfied requirement keeps the real action,
        // an unsatisfied one gates on needsNewerApp (never tampered).
        let first = try await plan(packageID: "com.t.ver", name: "Ver", trust: [:], hashes: [:], sources: [:], isMigrated: false, openClipVersion: "1.5.0")
        let hash = first.hashes["com.t.ver"]!
        let compatible = try await plan(packageID: "com.t.ver", name: "Ver", trust: ["com.t.ver": "trusted"], hashes: ["com.t.ver": hash], sources: [:], isMigrated: true, appVersion: "1.6.0", openClipVersion: "1.5.0")
        XCTAssertFalse(compatible.actions[0] is GatedExtensionAction, "satisfied requirement keeps the real action")
        XCTAssertTrue(compatible.events.isEmpty)

        let incompatible = try await plan(packageID: "com.t.ver", name: "Ver", trust: ["com.t.ver": "trusted"], hashes: ["com.t.ver": hash], sources: [:], isMigrated: true, appVersion: "1.4.0", openClipVersion: "1.5.0")
        let gated = try XCTUnwrap(incompatible.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .needsNewerApp(required: "1.5.0"))
        XCTAssertEqual(incompatible.trust["com.t.ver"], "trusted", "version gating must not flip a trusted package to seen")
        XCTAssertTrue(incompatible.events.isEmpty)
    }

    func testGatedActionPerformReturnsReviewToast() async throws {
        let gated = GatedExtensionAction(
            packageID: "com.t.g", title: "G", icon: .symbol("wand.and.stars"),
            chrome: ActionChrome(badge: .extensionPkg("G"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.t.g")),
            reason: .notEnabled
        )
        XCTAssertEqual(gated.id, "com.t.g")
        XCTAssertEqual(GatedExtensionAction.reviewMessage(for: .notEnabled), "This extension isn't enabled yet — review it in Preferences.")
        XCTAssertEqual(GatedExtensionAction.reviewMessage(for: .needsNewerApp(required: "2.0.0")), "This extension needs OpenClip 2.0.0 or newer.")
    }
}