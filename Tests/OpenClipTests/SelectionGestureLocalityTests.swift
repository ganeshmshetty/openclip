import XCTest
@testable import OpenClip

final class SelectionGestureLocalityTests: XCTestCase {
    private let screens = SelectionGestureLocality.ScreenLayout(
        primaryMaxY: 1000,
        frames: [CGRect(x: 0, y: 0, width: 1440, height: 1000)]
    )

    /// Cocoa rect → AX (top-left) rect on the fixture layout.
    private func ax(_ cocoa: CGRect) -> CGRect {
        CGRect(x: cocoa.minX, y: screens.primaryMaxY - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    func testDoubleClickAdmitsTheWordUnderThePointer() {
        let word = ax(CGRect(x: 180, y: 192, width: 60, height: 18))
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: word, gesture: .multiClick(at: CGPoint(x: 200, y: 200)), screens: screens))
    }

    /// Issue #162: Chromium selects the closest word, here a faded-out control label ~100pt below
    /// the double-click on the video.
    func testDoubleClickRejectsAnInvisibleWordFarFromThePointer() {
        let hiddenLabel = ax(CGRect(x: 16, y: 80, width: 43, height: 18))
        XCTAssertFalse(SelectionGestureLocality.admits(
            axBounds: hiddenLabel, gesture: .multiClick(at: CGPoint(x: 256, y: 200)), screens: screens))
    }

    func testDoubleClickAllowsSmallSnapDistance() {
        let wordEndingLeftOfPointer = ax(CGRect(x: 150, y: 192, width: 40, height: 18))
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: wordEndingLeftOfPointer, gesture: .multiClick(at: CGPoint(x: 200, y: 200)), screens: screens))
    }

    func testDragAdmitsSelectionTouchingTheDragArea() {
        let lines = ax(CGRect(x: 100, y: 300, width: 400, height: 60))
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: lines,
            gesture: .drag(from: CGPoint(x: 120, y: 350), to: CGPoint(x: 480, y: 310)),
            screens: screens))
    }

    func testDragAdmitsBackwardDrag() {
        let line = ax(CGRect(x: 100, y: 300, width: 400, height: 18))
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: line,
            gesture: .drag(from: CGPoint(x: 480, y: 308), to: CGPoint(x: 120, y: 308)),
            screens: screens))
    }

    func testDragRejectsSelectionElsewhere() {
        let staleSelection = ax(CGRect(x: 900, y: 700, width: 200, height: 18))
        XCTAssertFalse(SelectionGestureLocality.admits(
            axBounds: staleSelection,
            gesture: .drag(from: CGPoint(x: 120, y: 350), to: CGPoint(x: 480, y: 310)),
            screens: screens))
    }

    /// Rex: dragging upward from just below a wide block anchors on the first selected line, so
    /// AX reports only that line's box, sitting ~29pt above the drag start. The selection is real
    /// and spans the drag; the line box must not be rejected for missing the drag rectangle.
    func testDragAdmitsSelectionWhoseFirstLineSitsJustAboveTheStart() {
        let firstLine = ax(CGRect(x: 315, y: 680, width: 1036, height: 14))
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: firstLine,
            gesture: .drag(from: CGPoint(x: 317.35, y: 639.27), to: CGPoint(x: 709.99, y: 267.50)),
            screens: screens))
    }

    func testDragStillRejectsSelectionWellAboveTheLineSnapSlack() {
        let staleLine = ax(CGRect(x: 120, y: 450, width: 300, height: 14))
        XCTAssertFalse(SelectionGestureLocality.admits(
            axBounds: staleLine,
            gesture: .drag(from: CGPoint(x: 120, y: 350), to: CGPoint(x: 480, y: 310)),
            screens: screens))
    }

    func testUnusableBoundsFailOpen() {
        let gesture = SelectionGestureLocality.Gesture.multiClick(at: CGPoint(x: 200, y: 200))
        for bounds in [nil, CGRect.zero, CGRect(x: 10, y: 10, width: 0, height: 18), .null,
                       CGRect(x: -50_000, y: -50_000, width: 100, height: 20),
                       CGRect(x: 56, y: 955, width: 1, height: 1)] {
            XCTAssertTrue(SelectionGestureLocality.admits(axBounds: bounds, gesture: gesture, screens: screens),
                          "\(String(describing: bounds)) says nothing about the selection's location")
        }
    }

    func testFlipUsesPrimaryDisplayOnSecondaryScreenAbove() {
        let layout = SelectionGestureLocality.ScreenLayout(
            primaryMaxY: 1000,
            frames: [CGRect(x: 0, y: 0, width: 1440, height: 1000), CGRect(x: 0, y: 1000, width: 1440, height: 900)]
        )
        // Cocoa y 1400 on the upper display is AX y -400.
        let word = CGRect(x: 180, y: -410, width: 60, height: 18)
        XCTAssertTrue(SelectionGestureLocality.admits(
            axBounds: word, gesture: .multiClick(at: CGPoint(x: 200, y: 1400)), screens: layout))
        XCTAssertFalse(SelectionGestureLocality.admits(
            axBounds: word, gesture: .multiClick(at: CGPoint(x: 200, y: 400)), screens: layout))
    }
}
