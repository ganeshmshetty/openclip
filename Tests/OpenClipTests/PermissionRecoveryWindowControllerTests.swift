// PermissionRecoveryWindowControllerTests.swift
// OpenClipTests
//
// Tests for PermissionRecoveryWindowController verifying dismissal delegation and callback idempotency.
import XCTest
@testable import OpenClip

@MainActor
final class PermissionRecoveryWindowControllerTests: XCTestCase {

    func testHandleCompleteInvokesCallbackOnceAndClosesWindow() {
        var completeCount = 0
        var dismissCount = 0

        let controller = PermissionRecoveryWindowController(
            isUpdate: true,
            onComplete: { completeCount += 1 },
            onDismiss: { dismissCount += 1 }
        )

        controller.handleComplete()
        // Second attempt to ensure idempotency
        controller.handleComplete()
        controller.handleDismiss()

        XCTAssertEqual(completeCount, 1)
        XCTAssertEqual(dismissCount, 0)
    }

    func testWindowWillCloseInvokesOnDismissOnlyOnce() {
        var completeCount = 0
        var dismissCount = 0

        let controller = PermissionRecoveryWindowController(
            isUpdate: false,
            onComplete: { completeCount += 1 },
            onDismiss: { dismissCount += 1 }
        )

        guard let window = controller.window else {
            XCTFail("Missing window")
            return
        }

        // Simulate title-bar close button notification
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertEqual(completeCount, 0)
        XCTAssertEqual(dismissCount, 1)
    }
}
