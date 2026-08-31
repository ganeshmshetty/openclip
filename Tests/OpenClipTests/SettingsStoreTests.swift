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

    @MainActor
    func testTypedSettingReadWrite() {
        XCTAssertEqual(store.get(.actionOrder), [])
        store.set(.actionOrder, value: ["builtin.copy", "builtin.paste"])
        XCTAssertEqual(store.get(.actionOrder), ["builtin.copy", "builtin.paste"])
    }

    @MainActor
    func testDisabledActionIDsDefault() {
        XCTAssertTrue(store.get(.disabledActionIDs).isEmpty)
        store.set(.disabledActionIDs, value: ["builtin.search"])
        XCTAssertEqual(store.get(.disabledActionIDs), ["builtin.search"])
    }

    @MainActor
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

    @MainActor
    func testPopupScaleReadWrite() {
        XCTAssertEqual(store.get(.popupScale), 3)
        store.set(.popupScale, value: 4)
        XCTAssertEqual(store.get(.popupScale), 4)
    }

    @MainActor
    func testPopupPageSizeReadWrite() {
        XCTAssertEqual(store.get(.popupPageSize), 7)
        store.set(.popupPageSize, value: 5)
        XCTAssertEqual(store.get(.popupPageSize), 5)
    }

    @MainActor
    func testMenuBarIconVisibilityDefaultsToShownAndRoundTrips() {
        XCTAssertTrue(store.get(.showMenuBarIcon))
        store.set(.showMenuBarIcon, value: false)
        XCTAssertFalse(store.get(.showMenuBarIcon))
    }

    @MainActor
    func testResultDeliveryDefaults() {
        XCTAssertEqual(store.get(.primaryClickBehavior), "paste")
        XCTAssertEqual(store.get(.secondaryClickBehavior), "copy")
    }

    @MainActor
    func testResultDeliveryRoundTrip() {
        store.set(.primaryClickBehavior, value: "preview")
        store.set(.secondaryClickBehavior, value: "paste")
        XCTAssertEqual(store.get(.primaryClickBehavior), "preview")
        XCTAssertEqual(store.get(.secondaryClickBehavior), "paste")
    }

    func testResultDeliveryPreferenceMapping() {
        XCTAssertEqual(ResultDeliveryPreference.allCases, [.preview, .paste, .copy])
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "preview"), .preview)
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "paste"), .paste)
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "copy"), .copy)
        XCTAssertNil(ResultDeliveryPreference(rawValue: "bogus"))
    }
}
