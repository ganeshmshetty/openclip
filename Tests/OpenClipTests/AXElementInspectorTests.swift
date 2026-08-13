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

    func testSelectedTextMarkerRangeFallsBackToWebAreaWhenFocusedElementExposesNoMarker() {
        let focusedEl = AXUIElementCreateApplication(100)
        let webAreaEl = AXUIElementCreateApplication(200)
        let dummyFocusedMarker = "focused-marker-range" as NSString
        let dummyWebMarker = "webarea-marker-range" as NSString

        // Case 1: Focused element exposes marker range -> returns focused element's range
        let fromFocused = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { element, _ in
                if CFEqual(element, focusedEl) { return dummyFocusedMarker }
                if CFEqual(element, webAreaEl) { return dummyWebMarker }
                return nil
            }
        )
        XCTAssertEqual(fromFocused as? NSString, dummyFocusedMarker)

        // Case 2: Focused element returns nil, webArea exposes marker range -> falls back to webArea
        let fromWebArea = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { element, _ in
                if CFEqual(element, webAreaEl) { return dummyWebMarker }
                return nil
            }
        )
        XCTAssertEqual(fromWebArea as? NSString, dummyWebMarker)

        // Case 3: Both yield nil -> returns nil
        let fromNeither = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { _, _ in nil }
        )
        XCTAssertNil(fromNeither)
    }
}