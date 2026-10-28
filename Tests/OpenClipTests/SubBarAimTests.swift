// SubBarAimTests.swift
import XCTest
import CoreGraphics
@testable import OpenClip

/// Screen coordinates, y up. The open sub-bar sits above a main bar whose next button is another group.
/// Non-group neighbors never reach `SubBarAim`; they stay on the immediate-neighbor grace path.
final class SubBarAimTests: XCTestCase {
    /// Visible sub-bar row, not the shadow ring. Wide enough that the path into it crosses the next group.
    private let subBarAbove = CGRect(x: 100, y: 200, width: 180, height: 34)

    func testSwitchDwellStaysInsideTheAdjacentGroupWindow() {
        XCTAssertGreaterThanOrEqual(SubBarAim.switchDwell, 0.15)
        XCTAssertLessThanOrEqual(SubBarAim.switchDwell, 0.25)
    }

    func testCrossingAdjacentGroupTowardSubBarKeepsCurrentRow() {
        // Group A is around (120, 167). Group B, the next group, is around (150, 185) on the way up.
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 120, y: 167),
            current: CGPoint(x: 150, y: 185),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .keepMovingToward)
    }

    func testContinuedMoveAcrossAdjacentGroupStillKeepsCurrentRow() {
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 140, y: 180),
            current: CGPoint(x: 155, y: 190),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .keepMovingToward)
    }

    func testMovingAlongTheBarOntoAdjacentGroupSwitchesImmediately() {
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 120, y: 167),
            current: CGPoint(x: 160, y: 167),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .switchToHovered)
    }

    func testMovingAwayFromOpenSubBarSwitchesImmediately() {
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 120, y: 167),
            current: CGPoint(x: 140, y: 150),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .switchToHovered)
    }

    func testRestingOnAdjacentGroupSwitchesOnceDwellElapses() {
        let parked = CGPoint(x: 150, y: 185)
        let jitter = CGPoint(x: 151, y: 185.5)
        XCTAssertEqual(
            SubBarAim.decision(previous: parked, current: jitter, subBarRect: subBarAbove, rested: 0),
            .keepResting
        )
        XCTAssertEqual(
            SubBarAim.decision(
                previous: parked,
                current: jitter,
                subBarRect: subBarAbove,
                rested: SubBarAim.switchDwell - 0.01
            ),
            .keepResting
        )
        XCTAssertEqual(
            SubBarAim.decision(
                previous: parked,
                current: jitter,
                subBarRect: subBarAbove,
                rested: SubBarAim.switchDwell
            ),
            .switchToHovered
        )
    }

    func testAimAtTheSubBarCornerStillCountsAsToward() {
        // Narrow row: this sample misses the raw edge and stays inside only because the corner is widened.
        let narrow = CGRect(x: 100, y: 200, width: 80, height: 34)
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 140, y: 170),
            current: CGPoint(x: 176, y: 196),
            subBarRect: narrow,
            rested: 0
        )
        XCTAssertEqual(decision, .keepMovingToward)
    }

    func testDownwardMoveTowardSubBarBelowKeepsCurrentRow() {
        let subBarBelow = CGRect(x: 100, y: 40, width: 180, height: 34)
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 120, y: 150),
            current: CGPoint(x: 150, y: 110),
            subBarRect: subBarBelow,
            rested: 0
        )
        XCTAssertEqual(decision, .keepMovingToward)
    }

    func testMovingUpAwayFromSubBarBelowSwitches() {
        let subBarBelow = CGRect(x: 100, y: 40, width: 180, height: 34)
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 120, y: 150),
            current: CGPoint(x: 160, y: 165),
            subBarRect: subBarBelow,
            rested: 0
        )
        XCTAssertEqual(decision, .switchToHovered)
    }

    func testLeavingTheSubBarTowardAnotherGroupSwitches() {
        let decision = SubBarAim.decision(
            previous: CGPoint(x: 150, y: 210),
            current: CGPoint(x: 150, y: 185),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .switchToHovered)
    }

    func testFirstSampleDoesNotSwitch() {
        let decision = SubBarAim.decision(
            previous: nil,
            current: CGPoint(x: 150, y: 185),
            subBarRect: subBarAbove,
            rested: 0
        )
        XCTAssertEqual(decision, .keepResting)
    }

    func testRestedPointerSwitchesWithoutAMovementSample() {
        let decision = SubBarAim.decision(
            previous: nil,
            current: CGPoint(x: 150, y: 185),
            subBarRect: subBarAbove,
            rested: SubBarAim.switchDwell
        )
        XCTAssertEqual(decision, .switchToHovered)
    }
}
