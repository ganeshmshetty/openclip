import XCTest
@testable import OpenClip

@MainActor
final class PopupPanelTests: XCTestCase {
    func testCanBecomeKeyFollowsAllowsKey() {
        let panel = PopupPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        panel.allowsKey = false
        XCTAssertFalse(panel.canBecomeKey)
    }
}
