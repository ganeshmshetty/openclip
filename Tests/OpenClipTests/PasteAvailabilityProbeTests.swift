import XCTest
import AppKit
@testable import OpenClip

/// Tests the menu-item classification used by `PasteAvailabilityProbe`. The probe's decision
/// logic is exercised with plain AX attribute values so a non-English menu can be covered
/// without spawning a live AX session.
final class PasteAvailabilityProbeTests: XCTestCase {

    func testPasteMatchByNonEnglishTitle_WhenNoCommandEquivalent() {
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "Coller", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "Einfügen", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "Pegar", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "уметни", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "umetni", cmdChar: nil, cmdCharModifiers: nil))
    }

    func testPasteMatchByCJKTitle() {
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "粘贴", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(title: "붙여넣기", cmdChar: nil, cmdCharModifiers: nil))
    }

    func testPasteMatchByCommandEquivalent_IndependentlyOfTitle() {
        // Additional modifiers like Shift should be rejected
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(
            title: "포함", cmdChar: "V", cmdCharModifiers: UInt(AXMenuItemModifiers.shift.rawValue)))
        // Zero modifiers matches regardless of casing
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(
            title: nil, cmdChar: "V", cmdCharModifiers: UInt(AXMenuItemModifiers().rawValue)))
        XCTAssertTrue(PasteAvailabilityProbe.isPaste(
            title: nil, cmdChar: "v", cmdCharModifiers: 0))
    }

    func testCopyMatchesCaseInsensitivelyAndRejectsExtraModifiers() {
        XCTAssertTrue(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "C", cmdModifiers: 0))
        XCTAssertTrue(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "c", cmdModifiers: 0))
        XCTAssertFalse(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "C", cmdModifiers: UInt(AXMenuItemModifiers.shift.rawValue)))
        XCTAssertFalse(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "C", cmdModifiers: UInt(AXMenuItemModifiers.option.rawValue)))
        XCTAssertFalse(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "C", cmdModifiers: UInt(AXMenuItemModifiers.control.rawValue)))
        XCTAssertFalse(AXMenuNavigator.matches(.copy, title: nil, identifier: nil, cmdChar: "C", cmdModifiers: UInt(AXMenuItemModifiers.noCommand.rawValue)))
    }

    func testNonPasteItemsAreRejected() {
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(title: "Copier", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(title: "Copy", cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(title: nil, cmdChar: nil, cmdCharModifiers: nil))
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(
            title: "Cut", cmdChar: "X", cmdCharModifiers: UInt(AXMenuItemModifiers.control.rawValue)))
    }

    func testNonCommandModifierTokenIsRejected() {
        XCTAssertFalse(PasteAvailabilityProbe.isPaste(
            title: nil, cmdChar: "V", cmdCharModifiers: UInt(AXMenuItemModifiers.noCommand.rawValue)))
    }
}