import XCTest
@testable import Core
@testable import OpenClip

final class CloudEndpointSettingsTests: XCTestCase {
    func testLegacyURLOnlyAppliesToCustom() {
        let store = MemorySettingsStore()
        store.set(.aiCloudCustomURL, value: "https://api.inceptionlabs.ai/v1")

        XCTAssertEqual(CloudEndpointSettings.customURL(for: .custom, store: store), "https://api.inceptionlabs.ai/v1")
        XCTAssertEqual(CloudEndpointSettings.customURL(for: .opencodeGo, store: store), "")
    }

    func testOverridesAreScopedByProvider() {
        let store = MemorySettingsStore()
        CloudEndpointSettings.setCustomURL("https://opencode.ai/zen/go/v1", for: .opencodeGo, store: store)

        XCTAssertEqual(CloudEndpointSettings.customURL(for: .opencodeGo, store: store), "https://opencode.ai/zen/go/v1")
        XCTAssertEqual(CloudEndpointSettings.customURL(for: .openai, store: store), "")
        XCTAssertEqual(CloudEndpointSettings.customURL(for: .custom, store: store), "")
    }

    func testSettingCustomMirrorsLegacyKey() {
        let store = MemorySettingsStore()
        CloudEndpointSettings.setCustomURL("https://proxy.example/v1", for: .custom, store: store)

        XCTAssertEqual(store.get(.aiCloudCustomURL), "https://proxy.example/v1")
        XCTAssertEqual(CloudEndpointSettings.customURL(for: .custom, store: store), "https://proxy.example/v1")
    }

    func testClearingCustomDoesNotResurrectLegacyValue() {
        let store = MemorySettingsStore()
        store.set(.aiCloudCustomURL, value: "https://old.example/v1")
        CloudEndpointSettings.setCustomURL("", for: .custom, store: store)

        XCTAssertEqual(CloudEndpointSettings.customURL(for: .custom, store: store), "")
    }

    func testMigrationMovesLegacyURLToCustomAndClearsModelCacheOnce() {
        let store = MemorySettingsStore()
        store.set(.aiCloudCustomURL, value: "https://api.inceptionlabs.ai/v1")
        CloudModelCatalog.save(["mercury"], for: .opencodeGo, store: store)

        CloudEndpointSettings.migrateLegacyCustomURLIfNeeded(store: store)

        XCTAssertEqual(CloudEndpointSettings.customURL(for: .custom, store: store), "https://api.inceptionlabs.ai/v1")
        XCTAssertEqual(CloudEndpointSettings.customURL(for: .opencodeGo, store: store), "")
        XCTAssertNil(CloudModelCatalog.cached(for: .opencodeGo, store: store))

        CloudModelCatalog.save(["fresh"], for: .opencodeGo, store: store)
        CloudEndpointSettings.migrateLegacyCustomURLIfNeeded(store: store)
        XCTAssertEqual(CloudModelCatalog.cached(for: .opencodeGo, store: store)?.models, ["fresh"])
    }

    func testSettingsCatalogIncludesPerProviderOverrides() {
        XCTAssertTrue(SettingsCatalog.aiKeys.contains { $0.name == "aiCloudCustomURLs" })
    }
}
