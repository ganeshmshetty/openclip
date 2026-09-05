import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let size = CGSize(width: 50, height: 50)

    // Popup should appear above release point for normal/upward drag (center alignment)
    func testNormalPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .center
        )
        // X: centered on release → 400 - 25 = 375
        XCTAssertEqual(frame.origin.x, 375)
        // Y: above release → 200 + 6 (gap) = 206
        XCTAssertEqual(frame.origin.y, 206)
    }

    func testLeftAlignmentPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .left
        )
        // X: left-aligned with firstActionCenterOffset (16 + 17 = 33) -> 400 - 33 = 367
        XCTAssertEqual(frame.origin.x, 367)
        XCTAssertEqual(frame.origin.y, 206)
    }

    func testRightAlignmentPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .right
        )
        // X: right-aligned with firstActionCenterOffset -> 400 - (50 - 33) = 383
        XCTAssertEqual(frame.origin.x, 383)
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

    func testAlignedXPositions() {
        let releaseX: CGFloat = 400
        let leftX = PopupPositioner.alignedX(releaseX: releaseX, width: 200, screenBounds: screen, alignment: .left)
        XCTAssertEqual(leftX, 400 - PopupPositioner.firstActionCenterOffset)

        let centerX = PopupPositioner.alignedX(releaseX: releaseX, width: 200, screenBounds: screen, alignment: .center)
        XCTAssertEqual(centerX, 400 - 100)

        let rightX = PopupPositioner.alignedX(releaseX: releaseX, width: 200, screenBounds: screen, alignment: .right)
        XCTAssertEqual(rightX, 400 - (200 - PopupPositioner.firstActionCenterOffset))
    }

    func testVerticalPositionAboveForcesPlacementAbove() {
        // Even with a downward drag that would normally place below, .above forces placement above
        let start = CGPoint(x: 400, y: 350)
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            mouseDownPoint: start,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .above
        )
        // Above release: 200 + 6 = 206
        XCTAssertEqual(frame.origin.y, 206)
        XCTAssertTrue(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testVerticalPositionAboveFlipsWhenNearTopEdge() {
        let release = CGPoint(x: 400, y: 580)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .above
        )
        // No room above (580 + 6 + 50 > 592), flips below: 580 - 50 - 6 = 524
        XCTAssertEqual(frame.origin.y, 524)
        XCTAssertFalse(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testVerticalPositionBelowForcesPlacementBelow() {
        // With an upward/horizontal drag, .below forces placement below
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .below
        )
        // Below release: 200 - 50 - 6 = 144
        XCTAssertEqual(frame.origin.y, 144)
        XCTAssertFalse(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testVerticalPositionBelowFlipsWhenNearBottomEdge() {
        let release = CGPoint(x: 400, y: 30)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release,
            popupSize: size,
            screenBounds: screen,
            verticalPosition: .below
        )
        // No room below (30 - 50 - 6 = -26 < 8), flips above: 30 + 6 = 36
        XCTAssertEqual(frame.origin.y, 36)
        XCTAssertTrue(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
    }

    func testCenterInScreen() {
        let screenBounds = CGRect(x: 100, y: 50, width: 800, height: 600)
        let popupSize = CGSize(width: 300, height: 200)
        let centered = PopupPositioner.centerInScreen(popupSize: popupSize, screenBounds: screenBounds)

        XCTAssertEqual(centered.origin.x, 100 + (800 - 300) / 2)
        XCTAssertEqual(centered.origin.y, 50 + (600 - 200) / 2)
        XCTAssertEqual(centered.width, 300)
        XCTAssertEqual(centered.height, 200)
    }

    func testSearchPaletteMidXAlignsWithButtonCenterWhenWithinBarEdge() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let barMaxX: CGFloat = 700
        let searchWidth: CGFloat = 312
        let buttonScreenMidX: CGFloat = 400

        let midX = PopupPositioner.searchPaletteMidX(
            buttonScreenMidX: buttonScreenMidX,
            searchWidth: searchWidth,
            barMaxX: barMaxX,
            screenBounds: screenBounds
        )

        // MidX aligns exactly with button center (400) because 400 + 156 = 556 <= 700
        XCTAssertEqual(midX, buttonScreenMidX)
        XCTAssertLessThanOrEqual(midX + searchWidth / 2, barMaxX)
    }

    func testSearchPaletteMidXCappedByBarRightEdge() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let barMaxX: CGFloat = 700
        let searchWidth: CGFloat = 312
        // Clicked search button near the far right of the bar
        let buttonScreenMidX: CGFloat = 685

        let midX = PopupPositioner.searchPaletteMidX(
            buttonScreenMidX: buttonScreenMidX,
            searchWidth: searchWidth,
            barMaxX: barMaxX,
            screenBounds: screenBounds
        )

        // Must be capped so palette right edge (midX + searchWidth / 2) does not exceed barMaxX
        XCTAssertEqual(midX, barMaxX - searchWidth / 2)
        XCTAssertEqual(midX + searchWidth / 2, barMaxX)
    }

    func testSearchPaletteMidXClampedByScreenEdges() {
        let screenBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let padding = PopupMetrics.popupPadding
        let searchWidth: CGFloat = 312

        // When barMaxX is very small (near left screen edge)
        let leftMidX = PopupPositioner.searchPaletteMidX(
            buttonScreenMidX: 50,
            searchWidth: searchWidth,
            barMaxX: 100,
            screenBounds: screenBounds
        )
        // Screen padding takes precedence so it never renders off-screen
        XCTAssertEqual(leftMidX, screenBounds.minX + padding + searchWidth / 2)
    }
}

