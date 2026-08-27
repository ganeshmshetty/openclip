import XCTest
@testable import Core
@testable import OpenClip

final class AXHelperClientTests: XCTestCase {
    @MainActor
    func testHelperUnavailableWhenMachServiceNonexistent() async {
        let client = AXHelperClient(machServiceName: "com.openclip.test.nonexistent")
        let isAvailable = await client.isHelperAvailable()
        XCTAssertFalse(isAvailable)
    }

    @MainActor
    func testFallbackToInProcessAXWhenHelperDisconnected() async {
        let clientGranted = AXHelperClient(
            machServiceName: "com.openclip.test.nonexistent",
            localPermissionChecker: { _ in true }
        )
        let grantedResult = await clientGranted.checkAccessibility(prompt: false)
        XCTAssertTrue(grantedResult)

        let clientDenied = AXHelperClient(
            machServiceName: "com.openclip.test.nonexistent",
            localPermissionChecker: { _ in false }
        )
        let deniedResult = await clientDenied.checkAccessibility(prompt: false)
        XCTAssertFalse(deniedResult)
    }

    @MainActor
    func testLocalFallbackPermissionQuery() {
        let client = AXHelperClient(
            machServiceName: "com.openclip.test.nonexistent",
            localPermissionChecker: { prompt in !prompt }
        )
        let falsePromptPermission = client.checkLocalAccessibilityPermission(prompt: false)
        XCTAssertTrue(falsePromptPermission)

        let truePromptPermission = client.checkLocalAccessibilityPermission(prompt: true)
        XCTAssertFalse(truePromptPermission)
    }
}
