import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    func testNormalPositioning() {
        let cursor = CGPoint(x: 100, y: 100)
        let size = CGSize(width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(for: cursor, popupSize: size, in: bounds)
        
        XCTAssertEqual(frame.origin.x, 116) // 100 + 16
        XCTAssertEqual(frame.origin.y, 116) // 100 + 16
        XCTAssertEqual(frame.width, 50)
        XCTAssertEqual(frame.height, 50)
    }
    
    func testRightEdgeOverflow() {
        let cursor = CGPoint(x: 790, y: 100)
        let size = CGSize(width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(for: cursor, popupSize: size, in: bounds)
        
        XCTAssertEqual(frame.origin.x, 742) // 800 - 50 - 8
    }
    
    func testLeftEdgeOverflow() {
        let cursor = CGPoint(x: -10, y: 100)
        let size = CGSize(width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(for: cursor, popupSize: size, in: bounds)
        
        XCTAssertEqual(frame.origin.x, 8) // 0 + 8
    }
    
    func testTopEdgeOverflow() {
        let cursor = CGPoint(x: 100, y: 590)
        let size = CGSize(width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(for: cursor, popupSize: size, in: bounds)
        
        XCTAssertEqual(frame.origin.y, 532) // 590 - 50 - 8 (flipped below cursor)
    }
    
    func testBottomEdgeOverflow() {
        let cursor = CGPoint(x: 100, y: -10)
        let size = CGSize(width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(for: cursor, popupSize: size, in: bounds)
        
        XCTAssertEqual(frame.origin.y, 8) // 0 + 8
    }
    
    func testSelectionBoundsPositioning() {
        let selectionBounds = CGRect(x: 200, y: 200, width: 100, height: 20)
        let popupSize = CGSize(width: 80, height: 40)
        let screenBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(forSelectionBounds: selectionBounds, popupSize: popupSize, in: screenBounds)
        
        // MidX = 250, popup width = 80 => X = 250 - 40 = 210
        XCTAssertEqual(frame.origin.x, 210)
        // maxY = 220, offset = 16 => Y = 236
        XCTAssertEqual(frame.origin.y, 236)
        XCTAssertEqual(frame.width, 80)
        XCTAssertEqual(frame.height, 40)
    }
}
