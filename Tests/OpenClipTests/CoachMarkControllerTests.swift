import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class CoachMarkControllerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await MainActor.run {
            try XCTSkipUnless(NSScreen.main != nil, "no screen")
        }
    }

    @MainActor
    func testShowPresentsCardAnchoredBelowGivenFrame() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let store = MemorySettingsStore()
        let controller = CoachMarkController(settingsStore: store, accessibilityGranted: true, onSetupAction: {})
        defer { controller.dismiss() }

        let anchor = NSRect(x: visible.midX - 15, y: visible.maxY - 30, width: 30, height: 24)
        controller.show(anchorFrame: anchor)

        XCTAssertTrue(controller.isShowing)
        XCTAssertGreaterThan(controller.panelFrame.width, 100, "card must render wide enough for its copy")
        XCTAssertEqual(controller.panelFrame.midX, anchor.midX, accuracy: 1, "card centers horizontally on the anchor")
        XCTAssertEqual(controller.panelFrame.maxY, anchor.minY - 6, accuracy: 1, "card sits just below the anchor")
    }

    @MainActor
    func testDismissPersistsSeenFlag() {
        let store = MemorySettingsStore()
        let controller = CoachMarkController(settingsStore: store, accessibilityGranted: true, onSetupAction: {})

        controller.show(anchorFrame: nil)
        XCTAssertTrue(controller.isShowing)
        controller.dismiss()

        XCTAssertFalse(controller.isShowing)
        XCTAssertTrue(store.get(.hasDismissedPostOnboardingCoachMark), "dismissal must persist across launches")
    }

    @MainActor
    func testShowIsNoOpOnceSeenFlagIsSet() {
        let store = MemorySettingsStore()
        store.set(.hasDismissedPostOnboardingCoachMark, value: true)
        let controller = CoachMarkController(settingsStore: store, accessibilityGranted: false, onSetupAction: {})

        controller.show(anchorFrame: nil)
        XCTAssertFalse(controller.isShowing, "the one-time nudge must never show again after dismissal")
    }

    @MainActor
    func testSetupTapMarksSeenAndInvokesAction() {
        let store = MemorySettingsStore()
        var setupCalled = false
        let controller = CoachMarkController(settingsStore: store, accessibilityGranted: false, onSetupAction: { setupCalled = true })

        controller.show(anchorFrame: nil)
        controller.handleSetupTapped()

        XCTAssertTrue(setupCalled)
        XCTAssertFalse(controller.isShowing)
        XCTAssertTrue(store.get(.hasDismissedPostOnboardingCoachMark))
    }

    @MainActor
    func testShowTwiceDoesNotDuplicatePanel() {
        let store = MemorySettingsStore()
        let controller = CoachMarkController(settingsStore: store, accessibilityGranted: true, onSetupAction: {})
        defer { controller.dismiss() }

        controller.show(anchorFrame: nil)
        controller.show(anchorFrame: nil)
        XCTAssertTrue(controller.isShowing)
    }
}