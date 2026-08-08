import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupKeyModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StatusBadgeModel.shared.currentStatusBadge = nil
    }

    private func shownController() throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = PopupWindowController()
        controller.show(for: SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        ))
        return controller
    }

    func testShowCapturesFrontmostAppOnce() throws {
        let controller = try shownController()
        defer { controller.hide() }
        XCTAssertNotNil(controller.previousFrontmostApp, "show must capture the source app")
        let captured = controller.previousFrontmostApp
        controller.enterSearch()
        XCTAssertEqual(controller.previousFrontmostApp, captured, "re-entry must not re-capture")
    }

    func testKeyedPanelNeverStoresOpenClip() throws {
        // The self-capture guard runs in show(for:), not in enterSearch: asserting the frontmost
        // app right after enterSearch is non-deterministic on headless CI, where the runner
        // process (not the true source app) is frontmost. Assert at the capture site instead.
        let controller = try shownController()
        defer { controller.hide() }
        XCTAssertNotEqual(controller.previousFrontmostApp?.bundleIdentifier, Bundle.main.bundleIdentifier,
                          "a session must never store OpenClip itself as the source app")
        // The capture is a show(for:) artifact, not a post-enterSearch side effect: re-entering
        // search must not re-record the frontmost.
        let capturedAtShow = controller.previousFrontmostApp
        controller.enterSearch()
        controller.exitSearch()
        XCTAssertEqual(controller.previousFrontmostApp, capturedAtShow,
                       "only show(for:) captures the source app; enterSearch never re-captures")
        // hide() ends the session and clears; the next show() re-records whatever is frontmost then.
        controller.hide()
        XCTAssertNil(controller.previousFrontmostApp, "hide() clears the session capture")
    }

    func testExitSearchKeepsFrontmostApp() throws {
        let controller = try shownController()
        defer { controller.hide() }
        let captured = controller.previousFrontmostApp
        controller.enterSearch()
        controller.exitSearch()
        XCTAssertEqual(controller.previousFrontmostApp, captured,
                       "exitSearch must not clear the session source app")
        controller.enterSearch()
        XCTAssertEqual(controller.previousFrontmostApp, captured,
                       "re-entering search after exit must reuse the original source app")
    }

    func testHideClearsFrontmostApp() throws {
        let controller = try shownController()
        controller.enterSearch()
        controller.exitSearch()
        controller.hide()
        XCTAssertNil(controller.previousFrontmostApp, "only hide() ends the session")
    }

    func testSearchPanelBecomesKeyAndReturnsToNonKey() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController()
        defer { controller.hide() }
        let panel = try XCTUnwrap(NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) as? PopupPanel)
        controller.enterSearch()
        XCTAssertTrue(panel.allowsKey, "search mode must allow key (rule 9 exception)")
        controller.exitSearch()
        XCTAssertFalse(panel.allowsKey, "exit must restore the never-key invariant")
    }
}
