import XCTest
@testable import Core

final class ActionUsageStoreTests: XCTestCase {
    @MainActor
    private func makeStore() -> (UserDefaults, ActionUsageStore) {
        let defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        let store = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: defaults))
        return (defaults, store)
    }

    @MainActor
    func testRecordBumpsMonotonicCounter() {
        let (_, store) = makeStore()
        XCTAssertTrue(store.recency.isEmpty)
        store.record("builtin.search")
        store.record("builtin.copy")
        XCTAssertEqual(store.recency["builtin.search"], 1)
        XCTAssertEqual(store.recency["builtin.copy"], 2)
    }

    @MainActor
    func testMostRecentActionHasHighestCounter() {
        let (_, store) = makeStore()
        store.record("builtin.search")
        store.record("builtin.copy")
        store.record("builtin.search")
        XCTAssertGreaterThan(store.recency["builtin.search"]!, store.recency["builtin.copy"]!)
    }

    @MainActor
    func testRecencyPersistsAcrossInstances() {
        let (defaults, store) = makeStore()
        store.record("builtin.search")
        let reloaded = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: defaults))
        XCTAssertEqual(reloaded.recency["builtin.search"], 1)
    }

    @MainActor
    func testResetClearsHistory() {
        let (_, store) = makeStore()
        store.record("builtin.search")
        store.reset()
        XCTAssertTrue(store.recency.isEmpty)
    }

    @MainActor
    func testRecordSurvivesCounterOverflow() {
        let (defaults, _) = makeStore()
        defaults.set(["builtin.search": Int.max], forKey: "actionUsageRecency")
        let store = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: defaults))

        store.record("builtin.copy")
        XCTAssertEqual(store.recency, ["builtin.copy": 1], "counter at Int.max must reset rather than trap")
    }
}
