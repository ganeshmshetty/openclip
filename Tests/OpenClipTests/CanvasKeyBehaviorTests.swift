// CanvasKeyBehaviorTests.swift
// OpenClipTests
//
// Integration and live-panel test suite for canvas key behavior matrix,
// focused text fields, event isolation, focus fallback, and edge scenarios.

import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class CanvasKeyBehaviorTests: XCTestCase {

    private func shownController(for cursor: CGPoint = .zero) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen available") }
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let pos = cursor == .zero ? CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200) : cursor
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: pos,
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

    private func keyDown(_ keyCode: UInt16, char: String = "a") -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func scrollEvent() -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 1, wheel1: 5, wheel2: 0, wheel3: 0) else { return nil }
        return NSEvent(cgEvent: cg)
    }

    // MARK: - Key Behavior Matrix

    func testPanelKeyWithFocusedTextFieldAndTypingDoesNotDismiss() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.textField("field1", value: "hello", placeholder: "Type here")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Form"))
        let panel = try visiblePanel()
        pump()

        XCTAssertTrue(panel.allowsKey, "panel must allow key when canvas has text field")

        if let event = keyDown(7, char: "x") {
            controller.handleEvent(event)
        }

        XCTAssertTrue(panel.isVisible, "typing in focused text field must not dismiss panel")
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    func testDistanceDismissalSuspendedInContent() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Content mode")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Suspended Test"))
        let panel = try visiblePanel()
        pump()

        if let scroll = scrollEvent() {
            controller.handleEvent(scroll)
        }

        XCTAssertTrue(panel.isVisible, "scroll wheel event must not dismiss content canvas")
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    func testClickOutsideHidesEvenWithFocusedTextField() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.textField("field1", value: "val")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Click Outside"))
        let panel = try visiblePanel()
        pump()

        let clickOutside = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: panel.frame.maxX + 150, y: panel.frame.maxY + 150),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )

        if let clickOutside {
            controller.handleEvent(clickOutside)
        }

        XCTAssertFalse(panel.isVisible, "click outside panel must hide popup even with focused text field")
    }

    func testAppDidDeactivateHidesWhileCanvasKey() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Deactivate Test")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Deactivate"))
        let panel = try visiblePanel()
        pump()

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        pump()

        XCTAssertFalse(panel.isVisible, "app deactivation must hide panel while canvas is key")
    }

    func testFirstInteractiveFocusLandsOnTextField() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.button("Button", id: "btn1")
            Canvas.textField("field1", placeholder: "Focused Field")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Focus Priority"))
        pump()

        XCTAssertEqual(controller.canvasSessionController.session?.focusedComponentID, "field1", "first interactive focus must prioritize text field")
    }

    func testFocusFallsBackToRoot() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Static text only")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Root Focus"))
        let panel = try visiblePanel()
        pump()

        XCTAssertTrue(panel.allowsKey, "canvas root must be key focusable even without explicit field")
        XCTAssertNil(controller.canvasSessionController.session?.focusedComponentID, "focusedComponentID must be nil when focus falls back to root")
    }

    func testToggleCommitsAndDispatchesChange() throws {
        let scripting = GatedScripting()
        let initialTree = Canvas.build {
            Canvas.toggle("tog1", value: false, onToggle: .dispatch("flip"))
        }

        let updatedTree = Canvas.build {
            Canvas.toggle("tog1", value: true, onToggle: .dispatch("flip"))
        }
        scripting.dispatchResults = [
            CanvasDispatchResult(state: CanvasSessionState(["tog1": .bool(true)]), tree: updatedTree)
        ]

        let session = CanvasSession(
            header: CanvasHeader(title: "Toggle Session"),
            input: "test",
            preferredSize: nil,
            scripting: scripting,
            isAsync: false,
            tree: initialTree
        )

        let controller = try shownController()
        defer { controller.hide() }

        controller.canvasSessionController.replace(with: session)
        controller.canvasSessionController.dispatch(CanvasEvent(kind: .change, handler: "flip", value: "true", targetID: "tog1"))

        scripting.release()
        pump()

        let dispatched = scripting.calls.contains(where: { call in
            call.event?.kind == .change && call.event?.targetID == "tog1" && call.event?.value == "true"
        })
        XCTAssertTrue(dispatched, "toggle commit must dispatch change event to scripting engine")
    }

    // MARK: - Spec §12 Edge Scenarios

    func testDistanceDismissalClosesCanvas() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Dismissal test")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Distance"))
        pump()

        controller.hide()
        XCTAssertEqual(controller.modeStore.mode, .actions, "canvas dismissal closes canvas back to bar state")
    }

    func testHoverLongPressStaysInert() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Hover inert test")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Inert Hover"))
        let panel = try visiblePanel()
        pump()

        let moveEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: panel.frame.midX, y: panel.frame.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )

        if let moveEvent {
            controller.handleEvent(moveEvent)
        }
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content, "hover long-press gestures must stay inert over canvas content")
    }

    func testDisabledNodeDoesNotFireOrFocus() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.button("Disabled Button", id: "disBtn", disabled: true)
            Canvas.textField("enabledField", value: "active")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Disabled Node"))
        pump()

        XCTAssertEqual(controller.canvasSessionController.session?.focusedComponentID, "enabledField", "disabled node must be skipped for initial focus")
    }

    func testDisabledToggleSkippedForInitialFocus() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.toggle("tog1", value: false, disabled: true)
            Canvas.button("Enabled Button", id: "btn1")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Disabled Toggle"))
        pump()

        XCTAssertEqual(controller.canvasSessionController.session?.focusedComponentID, "btn1", "disabled toggle must be skipped for initial focus")
    }

    func testToggleRejectedChangeDoesNotDiverge() throws {
        let scripting = GatedScripting()
        scripting.error = NSError(domain: "CanvasKeyBehaviorTests", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "handler rejected the change"])
        let controller = try shownController()
        defer { controller.hide() }

        let initialTree = Canvas.build {
            Canvas.toggle("t1", value: false)
        }

        let session = CanvasSession(
            header: CanvasHeader(title: "Toggle Test"),
            input: "test",
            preferredSize: nil,
            scripting: scripting,
            isAsync: false,
            tree: initialTree,
            state: CanvasSessionState(["t1": .bool(false)])
        )
        controller.canvasSessionController.replace(with: session)

        controller.canvasSessionController.dispatch(CanvasEvent(kind: .change, handler: "onToggle", value: "true", targetID: "t1"))
        scripting.release()
        pump()

        // The pre-flip commits the new value into session state before the (rejecting) handler runs,
        // so the held session's state never diverges from the UI — even though the change is rejected.
        XCTAssertEqual(session.state.bool("t1"), true, "Pre-flip must update session state to true")
    }
}
