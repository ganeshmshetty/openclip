import XCTest
import ApplicationServices
import CoreGraphics
@testable import OpenClip

final class AXElementInspectorTests: XCTestCase {
    func testTargetMemberwiseInitBuildsFullyPopulatedFixture() {
        let target = AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXTextField",
            subRole: "AXSearchField",
            parentRoles: ["AXGroup", "AXWindow"],
            containedInRoles: ["AXWindow", "AXScrollArea"],
            webArea: nil,
            selectedText: "hello",
            selectedTextMarkerRange: nil,
            value: "hello",
            selectedTextRange: nil,
            bounds: CGRect(x: 1, y: 2, width: 30, height: 4)
        )

        XCTAssertEqual(target.role, "AXTextField")
        XCTAssertEqual(target.subRole, "AXSearchField")
        XCTAssertEqual(target.parentRoles, ["AXGroup", "AXWindow"])
        XCTAssertEqual(target.containedInRoles, ["AXWindow", "AXScrollArea"])
        XCTAssertEqual(target.selectedText, "hello")
        XCTAssertEqual(target.value, "hello")
        XCTAssertEqual(target.bounds, CGRect(x: 1, y: 2, width: 30, height: 4))
        XCTAssertNil(target.focusedApp)
        XCTAssertNil(target.focusedElement)
        XCTAssertNil(target.webArea)
        XCTAssertNil(target.selectedTextMarkerRange)
        XCTAssertNil(target.selectedTextRange)
    }

    func testTargetMemberwiseInitBuildsEmptyFixture() {
        let target = AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: nil,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: nil,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )

        XCTAssertNil(target.role)
        XCTAssertNil(target.subRole)
        XCTAssertTrue(target.parentRoles.isEmpty)
        XCTAssertTrue(target.containedInRoles.isEmpty)
        XCTAssertNil(target.selectedText)
        XCTAssertNil(target.value)
        XCTAssertNil(target.bounds)
    }

    func testAncestorWalkDepthIsBounded() {
        XCTAssertEqual(AXElementInspector.ancestorWalkDepth, 4)
    }
}