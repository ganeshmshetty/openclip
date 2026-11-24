import XCTest
import SwiftUI
@testable import OpenClip

final class PermissionCopyTests: XCTestCase {
    func testPrivacyPaneNameFollowsTheOS() {
        if #available(macOS 27.0, *) {
            XCTAssertEqual(PermissionCopy.paneName, "Device Control and Data Access")
            XCTAssertEqual(PermissionCopy.accessTitle, "Device Control and Data Access")
            XCTAssertEqual(PermissionCopy.accessTitleKey, "Device Control and Data Access")
            XCTAssertEqual(PermissionCopy.requiredTitle, "Device Control and Data Access Required")
        } else {
            XCTAssertEqual(PermissionCopy.paneName, "Accessibility")
            XCTAssertEqual(PermissionCopy.accessTitle, "Accessibility Access")
            XCTAssertEqual(PermissionCopy.accessTitleKey, "Accessibility Access")
            XCTAssertEqual(PermissionCopy.requiredTitle, "Accessibility Access Required")
        }
    }
}
