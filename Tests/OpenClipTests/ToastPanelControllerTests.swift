import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

final class ToastPanelControllerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await MainActor.run {
            TestIsolation.reset()
            UserDefaults.standard.removeObject(forKey: SettingKey.popupScale.name)
            UserDefaults.standard.removeObject(forKey: SettingKey.popupTheme.name)
            UserDefaults.standard.removeObject(forKey: SettingKey.popupThemeColor.name)
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
        XCTAssertLessThan(controller.panelFrame.height, 26 + 2 * PopupMetrics.toastShadowInset, "toast panel should be a slim single line (plus its shadow ring)")
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

    /// The toast must center directly in-place over the anchored popup frame — linked to the
    /// popup surface, never the cursor.
    @MainActor
    func testAnchorsCenteredOnPopupFrame() {
        let controller = ToastPanelController()
        let popup = NSRect(x: 400, y: 420, width: 220, height: 44)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"), anchorFrame: popup)
        XCTAssertEqual(controller.panelFrame.midX, popup.midX, accuracy: 1)
        XCTAssertEqual(controller.panelFrame.midY, popup.midY, accuracy: 1)
        XCTAssertEqual(controller.lastAnchorFrame, popup)
        XCTAssertGreaterThan(controller.panelFrame.width, 0)
        controller.hide()
    }

    /// When near screen boundaries, the toast stays clamped within the visible frame.
    @MainActor
    func testClampsToVisibleFrameWhenPopupNearEdge() throws {
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let controller = ToastPanelController()
        let popup = NSRect(x: 300, y: visible.minY + 2, width: 200, height: 40)
        controller.show(StatusFeedback(message: "Copied", style: .success), anchorFrame: popup)
        XCTAssertEqual(controller.panelFrame.midX, popup.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(controller.panelFrame.minY + PopupMetrics.toastShadowInset, visible.minY)
        controller.hide()
    }

    /// A follow-up show without an anchor (e.g. a loading spinner settling) stays attached to the
    /// same popup frame instead of moving.
    @MainActor
    func testShowWithoutAnchorReusesLastPopupFrame() {
        let controller = ToastPanelController()
        let popup = NSRect(x: 500, y: 460, width: 240, height: 44)
        controller.showLoading(message: "Opening…", anchorFrame: popup)
        controller.swapTo(StatusFeedback(message: "Done", style: .info))
        XCTAssertEqual(controller.panelFrame.midX, popup.midX, accuracy: 1)
        XCTAssertEqual(controller.panelFrame.midY, popup.midY, accuracy: 1)
        controller.hide()
    }

    /// With no anchor at all the toast centers deterministically on the main screen — it must
    /// never fall back to chasing the pointer.
    @MainActor
    func testWithoutAnyAnchorCentersOnMainScreenNotCursor() throws {
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let controller = ToastPanelController()
        controller.show(StatusFeedback(message: "Copied", style: .success))
        XCTAssertNil(controller.lastAnchorFrame)
        XCTAssertEqual(controller.panelFrame.midX, visible.midX, accuracy: 1)
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

    /// Regression: the toast must scale with the user's Popup Scale preference, matching the popup
    /// bar it attaches to. `ToastView` reads `SettingKey.popupScale` via @AppStorage; a larger scale
    /// must produce a larger bubble (and vice-versa). The default level 3 must stay byte-identical
    /// to the legacy fixed layout (baseline 77×24), so only the relative growth is asserted.
    @MainActor
    func testToastScalesWithPopupScale() {
        let defaults = UserDefaults.standard
        let key = SettingKey.popupScale.name
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let controller = ToastPanelController()

        defaults.set(5, forKey: key)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        let largeSize = controller.panelFrame.size
        controller.hide()

        defaults.set(1, forKey: key)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        let smallSize = controller.panelFrame.size
        controller.hide()

        XCTAssertGreaterThan(largeSize.height, smallSize.height, "toast panel height must grow with popupScale")
        XCTAssertGreaterThan(largeSize.width, smallSize.width, "toast panel width must grow with popupScale")
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

    @MainActor
    func testLoadingToastIsInteractiveAndTogglesIgnoresMouseEvents() {
        let controller = ToastPanelController()
        controller.showLoading(message: "Opening…", onCancel: {})
        XCTAssertFalse(controller.panelIgnoresMouseEvents, "loading toast with onCancel must accept mouse events")

        controller.swapTo(StatusFeedback(message: "Done", style: .info))
        XCTAssertTrue(controller.panelIgnoresMouseEvents, "settled toast must ignore mouse events")
        controller.hide()
        XCTAssertTrue(controller.panelIgnoresMouseEvents, "hidden toast must ignore mouse events")
    }

    @MainActor
    func testLoadingToastPassiveWithoutCancelHandler() {
        let controller = ToastPanelController()
        controller.showLoading(message: "Opening…")
        XCTAssertTrue(controller.panelIgnoresMouseEvents, "loading toast without onCancel must ignore mouse events")
        controller.hide()
    }

    @MainActor
    func testLoadingToastReservesWidthForCancelMessage() {
        let controller = ToastPanelController()
        // Single character message is much narrower than "Cancel Task"
        controller.showLoading(message: "A", onCancel: {})
        let shortMessageWidth = controller.panelFrame.width
        controller.hide()

        let cancelFeedback = StatusFeedback(message: String(localized: "Cancel Task"), style: .info, isLoading: true)
        controller.show(cancelFeedback, onCancel: {})
        let cancelOnlyWidth = controller.panelFrame.width
        controller.hide()

        XCTAssertGreaterThanOrEqual(shortMessageWidth, cancelOnlyWidth - 2, "short loading message must reserve at least Cancel Task width")
    }
}
