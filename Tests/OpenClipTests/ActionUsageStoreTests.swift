import XCTest
@testable import Core

@MainActor
final class ActionUsageStoreTests: XCTestCase {
    var userDefaults: UserDefaults!
    var store: ActionUsageStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        store = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: userDefaults))
    }

    func testRecordBumpsMonotonicCounter() {
        XCTAssertTrue(store.recency.isEmpty)
        store.record("builtin.search")
        store.record("builtin.copy")
        XCTAssertEqual(store.recency["builtin.search"], 1)
        XCTAssertEqual(store.recency["builtin.copy"], 2)
    }

    func testMostRecentActionHasHighestCounter() {
        store.record("builtin.search")
        store.record("builtin.copy")
        store.record("builtin.search")
        XCTAssertGreaterThan(store.recency["builtin.search"]!, store.recency["builtin.copy"]!)
    }

    func testRecencyPersistsAcrossInstances() {
        store.record("builtin.search")
        let reloaded = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: userDefaults))
        XCTAssertEqual(reloaded.recency["builtin.search"], 1)
    }

    func testResetClearsHistory() {
        store.record("builtin.search")
        store.reset()
        XCTAssertTrue(store.recency.isEmpty)
    }

    func testRecordSurvivesCounterOverflow() {
        userDefaults.set(["builtin.search": Int.max], forKey: "actionUsageRecency")
        store = ActionUsageStore(settingsStore: DefaultSettingsStore(userDefaults: userDefaults))

        store.record("builtin.copy")
        XCTAssertEqual(store.recency, ["builtin.copy": 1], "counter at Int.max must reset rather than trap")
    }
}
