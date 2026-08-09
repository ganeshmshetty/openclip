import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupCanvasTests: XCTestCase {

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

    private func makeResultTree() -> (CanvasComponent, CanvasHeader) {
        let tree = Canvas.build {
            Canvas.text("The answer.")
            Canvas.button("Replace", icon: .symbol("arrow.triangle.2.circlepath"), handler: .effect(.paste("The answer.")))
            Canvas.button("Copy", icon: .symbol("doc.on.doc"), handler: .effect(.copy("The answer.")))
        }
        return (tree, CanvasHeader(title: "AI Result", icon: "sparkles"))
    }

    func testShowContentEntersContentModeAndGrowsPanel() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let barHeight = panel.frame.height
        XCTAssertGreaterThan(barHeight, 0)

        let (tree, header) = makeResultTree()
        controller.handleActionResult(.showContent(tree, header))

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.content?.header.title, "AI Result")
        XCTAssertNil(controller.modeStore.content?.scripting, "bridged content is a native session")

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && panel.frame.height <= barHeight + 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barHeight, "canvas should grow the panel")
    }

    func testShowContentTreeArmsSession() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let tree = CanvasComponent.stack(.init(), [
            .text(CanvasTextProps(content: "hello")),
            .button(CanvasButtonProps(title: "Go", handler: .effect(.copy("hello"))))
        ])
        controller.handleActionResult(.showContent(tree, CanvasHeader(title: "T", icon: nil)))
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertNil(controller.modeStore.content?.scripting, "tree results arm a native session")
    }

    func testExitContentReturnsToActionsAndShrinksPanel() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let barHeight = panel.frame.height

        let (tree, header) = makeResultTree()
        controller.handleActionResult(.showContent(tree, header))
        controller.exitContent()

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.content)

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && panel.frame.height > barHeight + 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertLessThanOrEqual(panel.frame.height, barHeight + 1, "exit should shrink the panel back to the bar")
    }

    func testContentModeMakesPanelKey() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let (tree, header) = makeResultTree()
        controller.handleActionResult(.showContent(tree, header))
        pump()

        XCTAssertTrue(panel.allowsKey, "content mode is key exactly like search (rule 10 exception)")
        XCTAssertTrue(panel.isKeyWindow)
        controller.exitContent()
        pump()
        XCTAssertFalse(panel.allowsKey, "collapse restores the never-key invariant")
    }

    func testEscFromFocusedTextFieldCollapsesCanvas() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        controller.armCanvasForTesting(tree: .stack(.init(), [
            .textField(CanvasTextFieldProps(id: "field", value: "x", onSubmit: nil)),
            .button(CanvasButtonProps(title: "Go", handler: .effect(.paste("y"))))
        ]), header: CanvasHeader(title: "Form", icon: nil))
        let panel = try visiblePanel()
        pump()

        XCTAssertTrue(panel.allowsKey, "a canvas with a textField becomes key")
        // M8: Esc collapse is owned by SwiftUI `.onKeyPress(.escape)` on the field/root, NOT the
        // controller-level NSEvent monitor (removed in Task 14) — so drive the SwiftUI responder
        // path: post the Esc keyDown into the keyed panel's key event pipeline. The event must
        // carry the panel's real windowNumber — a panel windowNumber: 0 key event is ignored by
        // SwiftUI's key handling (xcodebuild live check; plain panel.sendEvent was a no-op).
        let escEvent = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                      characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                                      isARepeat: false, keyCode: 53))
        panel.sendEvent(escEvent)   // reaches the focused field's .onKeyPress(.escape) → onExitContent()
        pump()
        XCTAssertEqual(controller.modeStore.mode, .actions, "Esc collapses even from a focused textField")
        // The never-key invariant collapse restores is `canBecomeKey == false`. `panel.isKeyWindow`
        // isn't asserted here: under xcodebuild the test host is the foreground app, so nothing can
        // take key status away from the panel after `exitKeyMode()` (production gives it to the
        // source app via previousFrontmostApp.activate) and the panel is the app's sole window.
        XCTAssertFalse(panel.canBecomeKey, "collapse restores the never-key invariant")
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

    func testStatusWithOpenCanvasQueuesUntilCollapse() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        pump()
        let (tree1, header1) = makeResultTree()
        controller.handleActionResult(.showContent(tree1, header1))
        XCTAssertNil(controller.modeStore.statusBanner, "canvas must clear any prior banner")

        controller.handleActionResult(.showStatus(StatusFeedback(message: "Done", style: .info)))

        XCTAssertNil(controller.modeStore.statusBanner, "status with a canvas open must not show a banner")

        controller.exitContent()
        XCTAssertEqual(controller.modeStore.statusBanner?.message, "Done",
                       "a queued status surfaces on the bar banner after the canvas collapses")
    }

    private func keyDown(_ keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "x",
                         charactersIgnoringModifiers: "x", isARepeat: false, keyCode: keyCode)
    }

    private func scrollEvent() -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 1, wheel1: 5, wheel2: 0, wheel3: 0) else { return nil }
        return NSEvent(cgEvent: cg)
    }

    func testNonEscKeystrokeInContentModeDoesNotDismiss() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let (tree2, header2) = makeResultTree()
        controller.handleActionResult(.showContent(tree2, header2))
        let panel = try visiblePanel()

        controller.handleEvent(try XCTUnwrap(keyDown(7))) // 'x'

        XCTAssertTrue(panel.isVisible, "a non-Esc key in content mode must not dismiss")
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    func testKeystrokeInActionsModeDismisses() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        controller.handleEvent(try XCTUnwrap(keyDown(7)))

        XCTAssertFalse(panel.isVisible, "actions mode: any keystroke dismisses")
    }

    func testKeystrokeInSearchModeIsIgnored() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        controller.enterSearch()
        let panel = try visiblePanel()

        controller.handleEvent(try XCTUnwrap(keyDown(7)))

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .search)
    }

    func testScrollWheelSuspendedInContentAndSearch() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        let (tree3, header3) = makeResultTree()
        controller.handleActionResult(.showContent(tree3, header3))
        controller.handleEvent(try XCTUnwrap(scrollEvent()))
        XCTAssertTrue(panel.isVisible, "scroll must not dismiss a content canvas")

        controller.exitContent()
        controller.enterSearch()
        controller.handleEvent(try XCTUnwrap(scrollEvent()))
        XCTAssertTrue(panel.isVisible, "scroll must not dismiss search mode")
    }

    func testScrollWheelInActionsModeDismisses() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        controller.handleEvent(try XCTUnwrap(scrollEvent()))

        XCTAssertFalse(panel.isVisible, "scroll away from an actions-mode popup dismisses")
    }
}
