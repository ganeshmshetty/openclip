import XCTest
import AppKit
@testable import OpenClip

/// AppKit resolves accessibility hit-tests on a helper thread. Overlay views must decline those calls
/// rather than assert the main actor, which traps under Swift 6 strict concurrency.
final class OverlayHitTestIsolationTests: XCTestCase {
    private final class UnsafeSendable<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    func testToastContainerDeclinesBackgroundHitTest() {
        let view = ToastContainerView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let box = UnsafeSendable(view)
        let done = expectation(description: "background hit test")

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertNil(box.value.hitTest(NSPoint(x: 20, y: 20)))
            done.fulfill()
        }

        wait(for: [done], timeout: 5)
    }

    func testPopupClickableRegionCheckRunsOffMain() {
        let done = expectation(description: "background region check")
        let bounds = NSRect(x: -40, y: -40, width: 80, height: 80)

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(PopupPanel.ContentView.isInsideClickableRegion(point: .zero, bounds: bounds))
            XCTAssertFalse(
                PopupPanel.ContentView.isInsideClickableRegion(point: NSPoint(x: 39, y: 39), bounds: bounds)
            )
            done.fulfill()
        }

        wait(for: [done], timeout: 5)
    }
}
