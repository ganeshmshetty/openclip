import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

final class ToastPanelControllerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await MainActor.run {
            try XCTSkipUnless(NSScreen.main != nil, "no screen")
        }
    }

    @MainActor
    func testShowPresentsFeedbackAndShows() {
        let controller = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        XCTAssertTrue(controller.isShowing)
        XCTAssertEqual(controller.currentFeedback?.message, "Copied")
        XCTAssertFalse(controller.isLoading)
        controller.hide()
    }

    /// Regression: the toast must size from laid-out content — not the hosting view's stale/large
    /// fitting size, and not the `.preferredContentSize` option (which reports 0 and lets the window
    /// auto-size to a constrained measurement that truncates the message to just the icon).
    @MainActor
    func testShownFrameIsCompactAndHoldsMessage() {
        let controller = ToastPanelController()
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        XCTAssertLessThan(controller.panelFrame.height, 26, "toast panel should be a slim single line")
        XCTAssertGreaterThan(controller.panelFrame.width, 40, "frame must be wide enough to fit the message text, not just the icon")
        XCTAssertGreaterThan(controller.panelFrame.width, 0, "toast must not render zero-sized")
        controller.hide()
    }

    @MainActor
    func testShowLoadingFlag() {
        let controller = ToastPanelController()
        controller.showLoading(message: "Opening Apple Music…")
        XCTAssertTrue(controller.isShowing)
        XCTAssertTrue(controller.isLoading)
        controller.hide()
    }

    @MainActor
    func testSwapToReplacesContent() {
        let controller = ToastPanelController()
        controller.showLoading(message: "Opening…")
        controller.swapTo(StatusFeedback(message: "Done", style: .info))
        XCTAssertEqual(controller.currentFeedback?.message, "Done")
        XCTAssertFalse(controller.isLoading)
        controller.hide()
    }

    /// The toast must center on the anchor point, not the cursor.
    @MainActor
    func testShowCentersOnAnchorPoint() {
        let controller = ToastPanelController()
        let anchor = CGPoint(x: 500, y: 400)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"), anchorPoint: anchor)
        let size = controller.panelFrame.size
        XCTAssertEqual(controller.panelFrame.midX, anchor.x, accuracy: 1)
        XCTAssertEqual(controller.panelFrame.midY, anchor.y, accuracy: 1)
        XCTAssertGreaterThan(size.width, 0)
        controller.hide()
    }

    @MainActor
    func testAutoDismissAfterDuration() async throws {
        let controller = ToastPanelController(autoDismissNanoseconds: 5_000_000)
        controller.show(StatusFeedback(message: "Copied", style: .success))
        let deadline = Date().addingTimeInterval(2.0)
        while controller.isShowing && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(controller.isShowing, "info toast should auto-dismiss")
    }

    @MainActor
    func testLoadingToastHasNoTimer() async throws {
        let controller = ToastPanelController(autoDismissNanoseconds: 5_000_000)
        controller.showLoading(message: "Opening…")
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(controller.isShowing, "loading toast must not auto-dismiss")
        controller.hide()
    }

    @MainActor
    func testKeepVisibleToastHasNoTimer() async throws {
        let controller = ToastPanelController(autoDismissNanoseconds: 5_000_000)
        controller.show(StatusFeedback(message: "Stick", style: .info, keepVisible: true))
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(controller.isShowing, "keep-visible toast must not auto-dismiss")
        controller.hide()
    }
}
