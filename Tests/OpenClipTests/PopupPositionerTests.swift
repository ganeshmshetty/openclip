import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let size = CGSize(width: 50, height: 50)

    // Popup should appear above release point for normal/upward drag
    func testNormalPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // X: centered on release → 400 - 25 = 375
        XCTAssertEqual(frame.origin.x, 375)
        // Y: above release → 200 + 6 (gap) = 206
        XCTAssertEqual(frame.origin.y, 206)
    }

    // Top-to-Bottom drag: mouse released below start point -> place popup BELOW cursor to avoid covering text
    func testDragDownPositioning() {
        let start = CGPoint(x: 400, y: 350)
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, mouseDownPoint: start, popupSize: size, screenBounds: screen
        )
        // Y: below release → 200 - 50 (height) - 6 (gap) = 144
        XCTAssertEqual(frame.origin.y, 144)
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
        // No room above (580+6+50=636 > 600-8=592), flip below: 580 - 50 - 6 = 524
        XCTAssertEqual(frame.origin.y, 524)
    }

    // Near bottom edge: popup should stay above and clamp
    func testBottomEdgeClamped() {
        let release = CGPoint(x: 400, y: 5)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        // y = 5 + 6 = 11 — fits above fine
        XCTAssertEqual(frame.origin.y, 11)
    }

    // Width changes must re-center on the release X so the bar never drifts off the cursor.
    func testCenteredXReanchorsOnResize() {
        let releaseX: CGFloat = 400
        let centeredWide = PopupPositioner.centeredX(releaseX: releaseX, width: 300, screenBounds: screen)
        XCTAssertEqual(centeredWide, 250, "wide popup centered on release X")

        let centeredNarrow = PopupPositioner.centeredX(releaseX: releaseX, width: 100, screenBounds: screen)
        XCTAssertEqual(centeredNarrow, 350, "narrow popup re-centered so the bar stays under the cursor")
    }

    func testCenteredXClampsToEdges() {
        let nearRight = PopupPositioner.centeredX(releaseX: 790, width: 300, screenBounds: screen)
        XCTAssertEqual(nearRight, screen.maxX - 300 - 8, "clamped to right padding edge")

        let nearLeft = PopupPositioner.centeredX(releaseX: 5, width: 300, screenBounds: screen)
        XCTAssertEqual(nearLeft, screen.minX + 8, "clamped to left padding edge")
    }

    func testScreenFrameResolutionInclusivelyMatchesEdges() {
        let screen1 = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screen2 = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

        // Point exactly on the boundary of screen 2 (x = 3840)
        let pointOnRightEdge = CGPoint(x: 3840, y: 500)
        let resolved = PopupPositioner.screenFrame(containing: pointOnRightEdge, screenFrames: [screen1, screen2])
        XCTAssertEqual(resolved, screen2)
    }
}
