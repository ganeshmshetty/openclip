import XCTest
@testable import OpenClip

final class CaptureTextAnchorTests: XCTestCase {
    func testPopupAnchorKeepsReleasePointWhenPointerHasNotMoved() {
        let anchor = CaptureTextPopupAnchor.resolve(
            releasePoint: CGPoint(x: 100, y: 200),
            mouseDownPoint: nil,
            currentPointer: CGPoint(x: 106, y: 202)
        )

        XCTAssertEqual(anchor.cursorPosition, CGPoint(x: 100, y: 200))
        XCTAssertNil(anchor.mouseDownLocation)
    }

    func testPopupAnchorFollowsMovedPointer() {
        let anchor = CaptureTextPopupAnchor.resolve(
            releasePoint: CGPoint(x: 100, y: 200),
            mouseDownPoint: nil,
            currentPointer: CGPoint(x: 140, y: 230)
        )

        XCTAssertEqual(anchor.cursorPosition, CGPoint(x: 140, y: 230))
        XCTAssertNil(anchor.mouseDownLocation)
    }

    func testPopupAnchorKeepsKnownDragStart() {
        let anchor = CaptureTextPopupAnchor.resolve(
            releasePoint: CGPoint(x: 100, y: 200),
            mouseDownPoint: CGPoint(x: 40, y: 180),
            currentPointer: CGPoint(x: 102, y: 201)
        )

        XCTAssertEqual(anchor.cursorPosition, CGPoint(x: 100, y: 200))
        XCTAssertEqual(anchor.mouseDownLocation, CGPoint(x: 40, y: 180))
    }
}
