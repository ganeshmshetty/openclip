import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class AISettingsSiblingImportTests: XCTestCase {
    func testSiblingBundleIDPairsDevAndRelease() {
        XCTAssertEqual(AIServiceManager.siblingBundleID(of: "com.openclip.OpenClip.dev"), "com.openclip.OpenClip")
        XCTAssertEqual(AIServiceManager.siblingBundleID(of: "com.openclip.OpenClip"), "com.openclip.OpenClip.dev")
        XCTAssertNil(AIServiceManager.siblingBundleID(of: "com.example.Other"))
    }

    func testUnconfiguredBuildAdoptsTheOtherBuildsSettings() {
        let source = MemorySettingsStore()
        source.set(.aiActiveProvider, value: "cloud")
        source.set(.aiCloudService, value: "google")
        source.set(.aiCloudModel, value: "gemini-flash-latest")
        let store = MemorySettingsStore()

        XCTAssertTrue(AIServiceManager.importAISettings(into: store, from: source))
        XCTAssertEqual(store.get(.aiActiveProvider), "cloud")
        XCTAssertEqual(store.get(.aiCloudService), "google")
        XCTAssertEqual(store.get(.aiCloudModel), "gemini-flash-latest")
    }

    func testConfiguredBuildKeepsItsOwnChoice() {
        let source = MemorySettingsStore()
        source.set(.aiActiveProvider, value: "cloud")
        let store = MemorySettingsStore()
        store.set(.aiActiveProvider, value: "local")

        XCTAssertFalse(AIServiceManager.importAISettings(into: store, from: source))
        XCTAssertEqual(store.get(.aiActiveProvider), "local")
    }

    func testNothingToImportWhenTheOtherBuildIsUnconfigured() {
        XCTAssertFalse(AIServiceManager.importAISettings(into: MemorySettingsStore(), from: MemorySettingsStore()))
    }
}
