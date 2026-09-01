import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupKeyModeTests: XCTestCase {

    private func makeController() -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        controller.startTestSession(for: SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 400, y: 400),
            timestamp: Date(),
            appPolicy: .default
        ))
        return controller
    }

    func testShowCapturesFrontmostAppOnce() {
        let controller = makeController()
        defer { controller.hide() }
        // The capture guard in show(for:) skips when OpenClip itself is frontmost (the test host
        // during xcodebuild test) or when no app is frontmost (headless CI), so previousFrontmostApp
        // may be nil here. The non-nil capture claim only holds when a non-OpenClip app is frontmost.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            XCTAssertEqual(controller.previousFrontmostApp, frontmost,
                           "show must capture the frontmost source app")
        }
        // Capture-once holds in every environment: re-entry must never re-capture.
        let capturedAtShow = controller.previousFrontmostApp
        controller.enterSearch()
        XCTAssertEqual(controller.previousFrontmostApp, capturedAtShow, "re-entry must not re-capture")
        controller.exitSearch()
        controller.enterSearch()
        XCTAssertEqual(controller.previousFrontmostApp, capturedAtShow,
                       "re-entry after exit must not re-capture")
    }

    func testKeyedPanelNeverStoresOpenClip() {
        let controller = makeController()
        defer { controller.hide() }
        XCTAssertNotEqual(controller.previousFrontmostApp?.bundleIdentifier, Bundle.main.bundleIdentifier,
                          "a session must never store OpenClip itself as the source app")
        let capturedAtShow = controller.previousFrontmostApp
        controller.enterSearch()
        controller.exitSearch()
        XCTAssertEqual(controller.previousFrontmostApp, capturedAtShow,
                       "only show(for:) captures the source app; enterSearch never re-captures")
        controller.hide()
        XCTAssertNil(controller.previousFrontmostApp, "hide() clears the session capture")
    }

    func testExitSearchKeepsFrontmostApp() {
        let controller = makeController()
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

    func testHideClearsFrontmostApp() {
        let controller = makeController()
        controller.enterSearch()
        controller.exitSearch()
        controller.hide()
        XCTAssertNil(controller.previousFrontmostApp, "only hide() ends the session")
    }

    func testSearchPanelBecomesKeyAndReturnsToNonKey() {
        let panel = PopupPanel()
        XCTAssertFalse(panel.allowsKey)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey)
        panel.allowsKey = false
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testSubBarEscapeInterception() {
        let controller = makeController()
        defer { controller.hide() }

        controller.modeStore.isSubBarActive = true
        guard let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            XCTFail("Failed to construct Escape key event")
            return
        }

        // First Escape closes the sub-bar, but does not call hide()
        controller.handleEvent(escEvent)
        XCTAssertFalse(controller.modeStore.isSubBarActive, "Escape should close the sub-bar")
        XCTAssertTrue(controller.isVisible, "First Escape should keep popup visible")

        // Second Escape dismisses the popup (calling hide())
        controller.handleEvent(escEvent)
        XCTAssertFalse(controller.isVisible, "Second Escape should dismiss the popup")
    }

    func testHideResetsSubBarActive() {
        let controller = makeController()
        controller.modeStore.isSubBarActive = true
        XCTAssertTrue(controller.modeStore.isSubBarActive)

        controller.hide()
        XCTAssertFalse(controller.modeStore.isSubBarActive, "hide() must reset isSubBarActive")
    }
}
