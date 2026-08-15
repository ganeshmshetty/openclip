import XCTest
@testable import Core

final class ExtensionTrustStateTests: XCTestCase {
    func testTrustStateRawValuesAreStableAcrossPersistedRecords() {
        XCTAssertEqual(ExtensionTrustState.seen.rawValue, "seen")
        XCTAssertEqual(ExtensionTrustState.trusted.rawValue, "trusted")
        XCTAssertEqual(ExtensionTrustState.revoked.rawValue, "revoked")
        XCTAssertEqual(ExtensionTrustState(rawValue: "trusted"), .trusted)
        XCTAssertNil(ExtensionTrustState(rawValue: "unknown"))
    }

    func testTrustChangeCarriesPackageIdentity() {
        let new = ExtensionTrustChange.newPackage(packageID: "com.example.words", name: "Word Tools")
        guard case .newPackage(let pid, let name) = new else { return XCTFail("expected newPackage") }
        XCTAssertEqual(pid, "com.example.words")
        XCTAssertEqual(name, "Word Tools")
    }
}

final class ExtensionTrustSettingKeyTests: XCTestCase {
    func testKeysRoundTripThroughMemoryStore() {
        let store = MemorySettingsStore()
        XCTAssertEqual(store.get(.extensionTrust), [:])
        XCTAssertEqual(store.get(.extensionTrustHashes), [:])
        XCTAssertEqual(store.get(.extensionSources), [:])
        XCTAssertFalse(store.get(.extensionTrustMigrated))

        store.set(.extensionTrust, value: ["com.example.words": "trusted"])
        store.set(.extensionTrustHashes, value: ["com.example.words": "abc123"])
        store.set(.extensionSources, value: ["com.example.words": "store"])
        store.set(.extensionTrustMigrated, value: true)

        XCTAssertEqual(store.get(.extensionTrust), ["com.example.words": "trusted"])
        XCTAssertEqual(store.get(.extensionTrustHashes), ["com.example.words": "abc123"])
        XCTAssertEqual(store.get(.extensionSources), ["com.example.words": "store"])
        XCTAssertTrue(store.get(.extensionTrustMigrated))
    }
}