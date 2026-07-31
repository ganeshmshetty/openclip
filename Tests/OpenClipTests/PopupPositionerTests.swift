import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let size = CGSize(width: 50, height: 50)

    // Popup should appear above the release point (centered X, gapped Y above)
    func testNormalPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // X: centered on release → 400 - 25 = 375
        XCTAssertEqual(frame.origin.x, 375)
        // Y: above release → 200 + 12 (gap) = 212
        XCTAssertEqual(frame.origin.y, 212)
    }

    // Near right edge: popup should be pushed left
    func testRightEdgeClamping() {
        let release = CGPoint(x: 790, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // X clamped: 800 - 50 - 8 = 742
        XCTAssertEqual(frame.origin.x, 742)
    }

    // Near left edge: popup should be pushed right
    func testLeftEdgeClamping() {
        let release = CGPoint(x: 5, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // X clamped: 0 + 8 = 8
        XCTAssertEqual(frame.origin.x, 8)
    }

    // Near top edge: popup should flip BELOW the release point
    func testTopEdgeFlipToBelow() {
        let release = CGPoint(x: 400, y: 580)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // No room above (580+12+50=642 > 600-8=592), flip below: 580 - 50 - 12 = 518
        XCTAssertEqual(frame.origin.y, 518)
    }

    // Near bottom edge: popup should stay above and clamp
    func testBottomEdgeClamped() {
        let release = CGPoint(x: 400, y: 5)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // y = 5 + 12 = 17 — fits above fine
        XCTAssertEqual(frame.origin.y, 17)
    }
}
