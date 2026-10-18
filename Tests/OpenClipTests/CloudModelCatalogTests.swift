import XCTest
@testable import OpenClip
import Core

final class CloudModelCatalogTests: XCTestCase {
    func testNonChatModelsAreFilteredOut() {
        XCTAssertTrue(CloudModelCatalog.isChatModel("gpt-5-mini"))
        XCTAssertTrue(CloudModelCatalog.isChatModel("claude-sonnet-5-5"))
        XCTAssertFalse(CloudModelCatalog.isChatModel("text-embedding-3-large"))
        XCTAssertFalse(CloudModelCatalog.isChatModel("whisper-1"))
        XCTAssertFalse(CloudModelCatalog.isChatModel("gpt-4o-mini-tts"))
        XCTAssertFalse(CloudModelCatalog.isChatModel("gemini-2.5-flash-image"))
    }

    func testOrderingIsNewestFirstAndDeduplicated() {
        let byDate = CloudModelCatalog.ordered([
            .init(id: "old", created: 100), .init(id: "new", created: 300), .init(id: "mid", created: 200), .init(id: "new", created: 300)
        ])
        XCTAssertEqual(byDate, ["new", "mid", "old"])

        let byName = CloudModelCatalog.ordered([
            .init(id: "gemini-2.5-pro", created: nil), .init(id: "gemini-3.1-pro", created: nil), .init(id: "gemini-10-pro", created: nil)
        ])
        XCTAssertEqual(byName, ["gemini-10-pro", "gemini-3.1-pro", "gemini-2.5-pro"])
    }

    func testCacheRoundTripAndFreshness() {
        let store = MemorySettingsStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(CloudModelCatalog.cached(for: .openai, store: store))
        CloudModelCatalog.save(["a", "b"], for: .openai, now: now, store: store)
        CloudModelCatalog.save([], for: .google, now: now, store: store)
        let snapshot = CloudModelCatalog.cached(for: .openai, store: store)
        XCTAssertEqual(snapshot?.models, ["a", "b"])
        XCTAssertNil(CloudModelCatalog.cached(for: .google, store: store))
        XCTAssertTrue(CloudModelCatalog.isFresh(snapshot!, now: now.addingTimeInterval(3_600)))
        XCTAssertFalse(CloudModelCatalog.isFresh(snapshot!, now: now.addingTimeInterval(CloudModelCatalog.cacheLifetime + 1)))
    }

    func testChoicesPreferLiveThenCacheThenFallbackAndKeepSavedModel() {
        let cached = CloudModelCatalog.Snapshot(fetchedAt: Date(), models: ["cached-1"])
        XCTAssertEqual(CloudModelCatalog.choices(live: ["live-1"], cached: cached, provider: .openai, current: nil), ["live-1"])
        XCTAssertEqual(CloudModelCatalog.choices(live: [], cached: cached, provider: .openai, current: nil), ["cached-1"])
        XCTAssertEqual(CloudModelCatalog.choices(live: [], cached: nil, provider: .openai, current: nil), CloudServiceProvider.openai.defaultModels)
        XCTAssertEqual(CloudModelCatalog.choices(live: ["live-1"], cached: nil, provider: .openai, current: "retired").first, "retired")
    }
}
