import XCTest
@testable import Core
@testable import OpenClip

final class SettingsStoreTests: XCTestCase {
    var userDefaults: UserDefaults!
    var store: DefaultSettingsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        store = DefaultSettingsStore(userDefaults: userDefaults)
    }

    func testTypedSettingReadWrite() {
        XCTAssertEqual(store.get(.actionOrder), [])
        store.set(.actionOrder, value: ["builtin.copy", "builtin.paste"])
        XCTAssertEqual(store.get(.actionOrder), ["builtin.copy", "builtin.paste"])
    }

    func testDisabledActionIDsDefault() {
        XCTAssertTrue(store.get(.disabledActionIDs).isEmpty)
        store.set(.disabledActionIDs, value: ["builtin.search"])
        XCTAssertEqual(store.get(.disabledActionIDs), ["builtin.search"])
    }

    func testActionOptionKeyNameAndRoundTrip() {
        let key = SettingKey.actionOption(actionID: "com.test.action", optionID: "prefix")
        XCTAssertEqual(key.name, "action.com.test.action.option.prefix")
        XCTAssertEqual(key.defaultValue, "")

        XCTAssertEqual(store.get(key), "")
        store.set(key, value: "hello")
        XCTAssertEqual(store.get(key), "hello")
        store.set(key, value: "")
        XCTAssertEqual(store.get(key), "")
    }
}
