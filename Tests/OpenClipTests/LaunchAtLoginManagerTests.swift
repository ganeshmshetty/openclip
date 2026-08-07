import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class LaunchAtLoginManagerTests: XCTestCase {
    @MainActor
    func testLaunchAtLoginManagerToggle() throws {
        // Injectable apply: the test verifies the published state transitions and that the
        // manager reports each change, without ever registering/unregistering a real login item.
        var applied: [Bool] = []
        let manager = LaunchAtLoginManager(apply: { applied.append($0) })
        let initialStatus = manager.isEnabled
        
        // Toggle status
        manager.isEnabled = !initialStatus
        XCTAssertEqual(manager.isEnabled, !initialStatus)
        XCTAssertEqual(applied.last, !initialStatus)
        
        // Revert status
        manager.isEnabled = initialStatus
        XCTAssertEqual(manager.isEnabled, initialStatus)
        XCTAssertEqual(applied.last, initialStatus)
    }
}
