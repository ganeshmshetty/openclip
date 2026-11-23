import XCTest
@testable import Core
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let inset = PopupMetrics.popupShadowInset
    private let cardSize = CGSize(width: 50, height: 50)
    /// Panel frames carry a transparent shadow ring on every edge, so the frame is the card plus two insets.
    private var size: CGSize {
        CGSize(width: cardSize.width + 2 * inset, height: cardSize.height + 2 * inset)
    }

    private func card(_ frame: CGRect) -> CGRect {
        frame.insetBy(dx: inset, dy: inset)
    }

    // Popup should appear above release point for normal/upward drag (center alignment)
    func testNormalPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .center
        )
        XCTAssertEqual(frame.origin.x, release.x - size.width / 2)
        XCTAssertEqual(frame.origin.y, release.y + PopupPositioner.visibleGap - inset)
    }

    func testLeftAlignmentPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .left
        )
        XCTAssertEqual(frame.origin.x, 400 - PopupPositioner.firstActionCenterOffset)
        XCTAssertEqual(frame.origin.y, release.y + PopupPositioner.visibleGap - inset)
    }

    func testRightAlignmentPositioning() {
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, alignment: .right
        )
        XCTAssertEqual(frame.origin.x, 400 - (size.width - PopupPositioner.firstActionCenterOffset))
        XCTAssertEqual(frame.origin.y, release.y + PopupPositioner.visibleGap - inset)
    }

    // Measure `visibleGap` to the visible card, excluding the panel's transparent shadow ring.
    func testVisibleCardKeepsGapFromReleasePoint() {
        let release = CGPoint(x: 400, y: 300)

        let above = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, verticalPosition: .above
        )
        XCTAssertEqual(card(above).minY - release.y, PopupPositioner.visibleGap)

        let below = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, verticalPosition: .below
        )
        XCTAssertEqual(release.y - card(below).maxY, PopupPositioner.visibleGap)

        let dragDown = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, mouseDownPoint: CGPoint(x: 400, y: 400), popupSize: size, screenBounds: screen
        )
        XCTAssertEqual(release.y - card(dragDown).maxY, PopupPositioner.visibleGap)

        let flipped = PopupPositioner.placeNearReleasePoint(
            releasePoint: CGPoint(x: 400, y: 580), popupSize: size, screenBounds: screen, verticalPosition: .above
        )
        XCTAssertEqual(580 - card(flipped).maxY, PopupPositioner.visibleGap, "near the top edge the card flips below with the same gap")
        XCTAssertFalse(PopupPositioner.isPlacedAbove(frame: flipped, releasePoint: CGPoint(x: 400, y: 580)))
    }

    func testOCRPopupStaysBesideTheRegionSelectionReleasePoint() {
        let releasePoint = CGPoint(x: 620, y: 310)
        let context = SelectionContext(
            text: "recognized text",
            cursorPosition: releasePoint,
            mouseDownLocation: CGPoint(x: 560, y: 340),
            selectionBounds: CGRect(x: 560, y: 280, width: 160, height: 90),
            source: .ocr
        )
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: CGSize(width: 180 + 2 * inset, height: 48 + 2 * inset),
            in: CGRect(x: 0, y: 0, width: 800, height: 600),
            alignment: .center,
            verticalPosition: .above
        )

        XCTAssertEqual(frame.midX, releasePoint.x)
        XCTAssertEqual(card(frame).minY - releasePoint.y, PopupPositioner.visibleGap)
        XCTAssertLessThan(card(frame).minY - releasePoint.y, PopupMetrics.dismissalDistance(for: screen))
    }

    func testOCRPopupUsesCurrentPointerAndNormalGapAfterRecognitionDelay() {
        let releasePoint = CGPoint(x: 220, y: 230)
        let currentPointer = CGPoint(x: 640, y: 390)
        let anchor = CaptureTextPopupAnchor.resolve(
            releasePoint: releasePoint,
            mouseDownPoint: CGPoint(x: 180, y: 250),
            currentPointer: currentPointer
        )
        let context = SelectionContext(
            text: "recognized text",
            cursorPosition: anchor.cursorPosition,
            mouseDownLocation: anchor.mouseDownLocation,
            selectionBounds: CGRect(x: 180, y: 210, width: 120, height: 80),
            source: .ocr
        )
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: CGSize(width: 180 + 2 * inset, height: 48 + 2 * inset),
            in: screen,
            alignment: .center,
            verticalPosition: .above
        )

        XCTAssertEqual(anchor.cursorPosition, currentPointer)
        XCTAssertNil(anchor.mouseDownLocation)
        XCTAssertEqual(frame.midX, currentPointer.x)
        XCTAssertEqual(card(frame).minY - currentPointer.y, PopupPositioner.visibleGap)
        let cardFrame = card(frame)
        let dx = max(0, max(cardFrame.minX - currentPointer.x, currentPointer.x - cardFrame.maxX))
        let dy = max(0, max(cardFrame.minY - currentPointer.y, currentPointer.y - cardFrame.maxY))
        XCTAssertEqual(hypot(dx, dy), PopupPositioner.visibleGap)
        XCTAssertLessThan(hypot(dx, dy), PopupMetrics.dismissalDistance(for: screen))
    }

    func testOCRArrivalGraceExpiresAndDoesNotBecomePermanent() {
        let deadline: TimeInterval = 15
        XCTAssertTrue(PopupDismissalGrace.isActive(now: 14.99, deadline: deadline))
        XCTAssertFalse(PopupDismissalGrace.isActive(now: deadline, deadline: deadline))
        XCTAssertFalse(PopupDismissalGrace.isActive(now: 30, deadline: nil))
    }

    // Top-to-Bottom drag: released below the start point, so the popup goes BELOW the cursor to avoid covering text.
    func testDragDownPositioning() {
        let start = CGPoint(x: 400, y: 350)
        let release = CGPoint(x: 400, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, mouseDownPoint: start, popupSize: size, screenBounds: screen
        )
        XCTAssertEqual(frame.origin.y, 102)
    }

    // Near right edge: popup should be pushed left
    func testRightEdgeClamping() {
        let release = CGPoint(x: 790, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        XCTAssertEqual(frame.origin.x, screen.maxX - size.width - 8)
    }

    // Near left edge: popup should be pushed right
    func testLeftEdgeClamping() {
        let release = CGPoint(x: 5, y: 200)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        XCTAssertEqual(frame.origin.x, 8)
    }

    // Near top edge: popup should flip BELOW the release point
    func testTopEdgeFlipToBelow() {
        let release = CGPoint(x: 400, y: 580)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen
        )
        XCTAssertEqual(frame.origin.y, 482)
    }

    // Near bottom edge with no room below: the card keeps its gap above the release point rather than
    // clamping the frame away from it.
    func testBottomEdgeKeepsVisibleGap() {
        let release = CGPoint(x: 400, y: 5)
        let frame = PopupPositioner.placeNearReleasePoint(
            releasePoint: release, popupSize: size, screenBounds: screen, verticalPosition: .above
        )
        XCTAssertEqual(card(frame).minY - release.y, PopupPositioner.visibleGap)
        XCTAssertGreaterThanOrEqual(card(frame).minY, screen.minY + 8)
    }

    func testCardOpensAboveOnlyWithinThresholdOfScreenBottom() {
        let justBelow = CGRect(
            x: 0,
            y: PopupMetrics.cardAboveThreshold - inset - 1,
            width: 100,
            height: 50
        )
        XCTAssertTrue(PopupPositioner.prefersCardAbove(frame: justBelow, screenBounds: screen))

        let atThreshold = justBelow.offsetBy(dx: 0, dy: 1)
        XCTAssertFalse(PopupPositioner.prefersCardAbove(frame: atThreshold, screenBounds: screen))
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
        XCTAssertEqual(frame.origin.y, 192)
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
        XCTAssertEqual(frame.origin.y, 482)
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
        XCTAssertEqual(frame.origin.y, 102)
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
        XCTAssertEqual(frame.origin.y, 22)
        XCTAssertTrue(PopupPositioner.isPlacedAbove(frame: frame, releasePoint: release))
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

        // Capped so the palette's right edge stays within the bar.
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
