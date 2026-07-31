import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class LaunchAtLoginManagerTests: XCTestCase {
    @MainActor
    func testLaunchAtLoginManagerToggle() throws {
        let manager = LaunchAtLoginManager.shared
        let initialStatus = manager.isEnabled
        
        // Toggle status
        manager.isEnabled = !initialStatus
        XCTAssertEqual(manager.isEnabled, !initialStatus)
        
        // Revert status
        manager.isEnabled = initialStatus
        XCTAssertEqual(manager.isEnabled, initialStatus)
    }
}
