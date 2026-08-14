import XCTest
@testable import Core

final class SelectionGatePolicyTests: XCTestCase {
    func testDefaultGateSkipsAXButtonAndAllowsUnknown() {
        XCTAssertTrue(SelectionGatePolicy.default.skipRoles.contains("AXButton"))
        XCTAssertTrue(SelectionGatePolicy.default.allowedCursors.contains(.unknown))
    }

    func testLenientGateHasNoSkippedRoles() {
        XCTAssertTrue(SelectionGatePolicy.lenient.skipRoles.isEmpty)
        XCTAssertEqual(SelectionGatePolicy.lenient.allowedCursors, [.beam, .arrow, .pointingHand, .unknown])
    }

    func testSelectionRetrievalModeCodableRoundTripsAllCases() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for mode in SelectionRetrievalMode.allCases {
            let decoded = try decoder.decode(SelectionRetrievalMode.self, from: encoder.encode(mode))
            XCTAssertEqual(mode, decoded)
        }
    }

    func testSelectionRetrievalModeDecodesKebabCaseRawValues() throws {
        let json = #"["ax-text-control","ax-web-area","browser-script","menu-copy","keyboard-copy"]"#
        let modes = try JSONDecoder().decode([SelectionRetrievalMode].self, from: Data(json.utf8))
        XCTAssertEqual(modes, SelectionRetrievalMode.allCases)
    }

    func testCursorClassCodableRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for cursor in CursorClass.allCases {
            let decoded = try decoder.decode(CursorClass.self, from: encoder.encode(cursor))
            XCTAssertEqual(cursor, decoded)
        }
    }
}