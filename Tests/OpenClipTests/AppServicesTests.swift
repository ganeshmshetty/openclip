import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class AppServicesTests: XCTestCase {
    func testAppServicesInitialization() {
        let services = AppServices.shared
        XCTAssertNotNil(services.settingsStore)
        XCTAssertNotNil(services.actionRegistry)
        XCTAssertNotNil(services.actionPresentation)
    }
}
