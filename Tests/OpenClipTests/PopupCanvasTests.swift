import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupCanvasTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StatusBadgeModel.shared.currentStatusBadge = nil
    }

    private func shownController(for cursor: CGPoint) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = PopupWindowController()
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: cursor,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        return controller
    }

    private func visiblePanel() throws -> PopupPanel {
        guard let panel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) as? PopupPanel else {
            throw XCTSkip("popup panel did not appear")
        }
        return panel
    }

    private func pump(_ duration: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    private func makeResultContent() -> PopupContent {
        PopupContent(
            title: "AI Result",
            icon: "sparkles",
            rows: [.text("The answer.")],
            footer: [
                ContentOption(title: "Replace", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste("The answer."))),
                ContentOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy("The answer.")))
            ],
            emphasis: .result
        )
    }

    func testShowContentEntersContentModeAndGrowsPanel() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let barHeight = panel.frame.height
        XCTAssertGreaterThan(barHeight, 0)

        controller.handleActionResult(.showContent(makeResultContent()))

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.content?.title, "AI Result")
        XCTAssertTrue(controller.modeStore.content?.emphasis == .result)

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && panel.frame.height <= barHeight + 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barHeight, "canvas should grow the panel")
    }

    func testExitContentReturnsToActionsAndShrinksPanel() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let barHeight = panel.frame.height

        controller.handleActionResult(.showContent(makeResultContent()))
        controller.exitContent()

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.content)

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && panel.frame.height > barHeight + 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertLessThanOrEqual(panel.frame.height, barHeight + 1, "exit should shrink the panel back to the bar")
    }

    func testContentModeKeepsPanelNonKey() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        controller.handleActionResult(.showContent(makeResultContent()))
        pump()

        XCTAssertFalse(panel.canBecomeKey, "content mode must preserve the never-key invariant (rule 9)")
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testStatusBannerWithoutCanvas() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        pump()
        controller.handleActionResult(.showStatus(StatusFeedback(message: "Copied", style: .success)))

        XCTAssertEqual(controller.modeStore.statusBanner?.message, "Copied")
        XCTAssertNil(controller.modeStore.content, "status must not open a canvas")
    }

    func testStatusBadgeWithOpenCanvas() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        pump()
        controller.handleActionResult(.showContent(makeResultContent()))
        XCTAssertNil(controller.modeStore.statusBanner, "canvas must clear any prior banner")

        controller.handleActionResult(.showStatus(StatusFeedback(message: "Done", style: .info)))

        XCTAssertNil(controller.modeStore.statusBanner, "status with a canvas open must not show a banner")
        XCTAssertEqual(StatusBadgeModel.shared.currentStatusBadge?.message, "Done",
                       "status with a canvas open surfaces as a corner badge")
    }
}
