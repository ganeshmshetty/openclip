import XCTest
@testable import OpenClip

final class CocoaWindowFrameIndexTests: XCTestCase {
    private let primaryWindow = CGRect(x: 100, y: 200, width: 400, height: 300)
    private let secondaryDisplayWindow = CGRect(x: 1512, y: -100, width: 800, height: 600)

    func testPointInsideAnyFrame() {
        let index = CocoaWindowFrameIndex(cocoaFrames: [primaryWindow, secondaryDisplayWindow])

        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: 300, y: 350)))
        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: 1600, y: 100)))
        XCTAssertFalse(index.contains(cocoaPoint: CGPoint(x: 900, y: 350)))
    }

    func testFrameEdgesUseCocoaHalfOpenBounds() {
        let index = CocoaWindowFrameIndex(cocoaFrames: [primaryWindow])

        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: primaryWindow.minX, y: primaryWindow.minY)))
        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: primaryWindow.maxX - 0.5, y: primaryWindow.maxY - 0.5)))
        XCTAssertFalse(index.contains(cocoaPoint: CGPoint(x: primaryWindow.maxX, y: primaryWindow.midY)))
        XCTAssertFalse(index.contains(cocoaPoint: CGPoint(x: primaryWindow.midX, y: primaryWindow.maxY)))
    }

    func testSecondDisplayOffsetUsesTheSameGlobalCoordinateSpace() {
        let index = CocoaWindowFrameIndex(cocoaFrames: [secondaryDisplayWindow])

        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: secondaryDisplayWindow.minX + 1, y: secondaryDisplayWindow.minY + 1)))
        XCTAssertFalse(index.contains(cocoaPoint: CGPoint(x: secondaryDisplayWindow.minX - 1, y: secondaryDisplayWindow.midY)))
        XCTAssertFalse(index.contains(cocoaPoint: CGPoint(x: primaryWindow.midX, y: primaryWindow.midY)))
    }

    func testEmptyFramesAndEmptyIndexNeverMatch() {
        let index = CocoaWindowFrameIndex(cocoaFrames: [.zero, .null, primaryWindow])

        XCTAssertFalse(index.contains(cocoaPoint: .zero))
        XCTAssertTrue(index.contains(cocoaPoint: CGPoint(x: primaryWindow.midX, y: primaryWindow.midY)))
        XCTAssertFalse(CocoaWindowFrameIndex(cocoaFrames: []).contains(cocoaPoint: CGPoint(x: 300, y: 350)))
    }
}
