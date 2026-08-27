import XCTest
@testable import Core
@testable import OpenClip

final class AXHelperHostTests: XCTestCase {
    @MainActor
    func testHelperURLResolutionFromBundle() {
        let host = AXHelperHost()
        let url = host.helperBundleURL()
        XCTAssertTrue(url.path.contains("Contents/Helpers") || url.path.contains("OpenClipAXHelper"))
        XCTAssertTrue(url.lastPathComponent == "\(AXHelperConstants.helperExecutableName).app")
    }

    @MainActor
    func testStartHelperWhenMissingDoesNotThrowOrCrash() {
        let host = AXHelperHost()
        // In the test environment, the helper app bundle won't exist inside the xctest bundle.
        // startHelperIfNeeded should log a notice and return gracefully.
        host.startHelperIfNeeded()
    }

    @MainActor
    func testStopHelperWhenNotRunningDoesNotCrash() {
        let host = AXHelperHost()
        host.stopHelper()
    }
}
