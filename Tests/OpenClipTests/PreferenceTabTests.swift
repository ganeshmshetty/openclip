import XCTest
@testable import OpenClip
@testable import Core

final class PreferenceTabTests: XCTestCase {
    @MainActor
    func testPreferenceTabCases() {
        let expectedCases: [PreferenceTab] = [
            .general,
            .appearance,
            .actions,
            .store,
            .appRules,
            .about
        ]
        XCTAssertEqual(PreferenceTab.allCases, expectedCases)
    }

    @MainActor
    func testStoreTabMetadata() {
        XCTAssertEqual(PreferenceTab.store.rawValue, "Store")
        XCTAssertEqual(PreferenceTab.store.icon, "bag.fill")
    }
}
