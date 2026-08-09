// CanvasSessionLifecycleTests.swift
// OpenClipTests
//
// Lifecycle and integration tests for content canvas sessions (spec §5 / §7 / §11).
// Tests session replacement, cancellation, error collapsing, keyboard-driven Esc collapse,
// status queuing across mode switches, and live panel interaction.

import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class CanvasSessionLifecycleTests: XCTestCase {

    private func textTree(_ content: String, id: String? = nil) -> CanvasComponent {
        .text(CanvasTextProps(id: id, content: content))
    }

    private func shownController(for cursor: CGPoint = .zero) throws -> PopupWindowController {
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

    private func pump(_ duration: TimeInterval = 0.05, rounds: Int = 4) {
        for _ in 0..<rounds {
            RunLoop.current.run(until: Date().addingTimeInterval(duration))
        }
    }

    // MARK: - Step 1: Lifecycle tests (unit, controller-level)

    func testNewMountReplacesSession() {
        let controller = CanvasSessionController()
        let sessionA = CanvasSession(header: CanvasHeader(title: "A"), input: "a", preferredSize: nil, scripting: nil, isAsync: false, tree: textTree("A"))
        let sessionB = CanvasSession(header: CanvasHeader(title: "B"), input: "b", preferredSize: nil, scripting: nil, isAsync: false, tree: textTree("B"))

        controller.replace(with: sessionA)
        XCTAssertEqual(controller.session?.header.title, "A")

        controller.replace(with: sessionB)
        XCTAssertEqual(controller.session?.header.title, "B")
        XCTAssertEqual(controller.session?.id, sessionB.id)
    }

    func testInflightDispatchDiscardedOnReplacement() {
        let controller = CanvasSessionController()
        let fakeA = GatedScripting()
        let sink = LocalEffectSink()
        controller.onEffects = { sink.effects.append($0) }

        let sessionA = CanvasSession(header: CanvasHeader(title: "A"), input: "a", preferredSize: nil, scripting: fakeA, isAsync: false, tree: textTree("A"), state: CanvasSessionState(["a": .number(1)]))
        controller.replace(with: sessionA)

        fakeA.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["a": .number(99)]), tree: textTree("A_modified"), effects: [.paste("fromA")])]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "btn"))
        pump()

        let sessionB = CanvasSession(header: CanvasHeader(title: "B"), input: "b", preferredSize: nil, scripting: nil, isAsync: false, tree: textTree("B"), state: CanvasSessionState(["b": .number(2)]))
        controller.replace(with: sessionB)

        fakeA.release()
        pump()

        XCTAssertEqual(controller.session?.id, sessionB.id)
        XCTAssertEqual(controller.session?.tree, textTree("B"))
        XCTAssertEqual(controller.session?.state["b"]?.numberValue, 2)
        XCTAssertEqual(sessionA.state["a"]?.numberValue, 1, "session A state must be untouched by late write-back")
        XCTAssertTrue(sink.effects.isEmpty, "no effects from discarded dispatch should be emitted")
    }

    func testHideCancelsInflightDispatchAndIgnoresLateResult() {
        let controller = CanvasSessionController()
        let fake = GatedScripting()
        let sink = LocalEffectSink()
        controller.onEffects = { sink.effects.append($0) }

        let session = CanvasSession(header: CanvasHeader(title: "S"), input: "s", preferredSize: nil, scripting: fake, isAsync: false, tree: textTree("S"), state: CanvasSessionState(["n": .number(0)]))
        controller.replace(with: session)

        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["n": .number(9)]), tree: textTree("S_modified"), effects: [.paste("x")])]

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "btn"))
        pump()

        controller.clear()
        fake.release()
        pump()

        XCTAssertNil(controller.session)
        XCTAssertEqual(session.state["n"]?.numberValue, 0, "cleared session receives no write-back")
        XCTAssertTrue(sink.effects.isEmpty)
    }

    func testLateMountResultAfterClearIsIgnored() {
        let controller = CanvasSessionController()
        let fake = GatedScripting()
        fake.mountResult = CanvasMountResult(state: CanvasSessionState(), tree: textTree("LateMount"))

        controller.mount(CanvasMountRequest(input: "in"), scripting: fake, header: CanvasHeader(title: "Late"))
        pump()

        controller.clear()
        fake.release()
        pump()

        XCTAssertNil(controller.session, "armed session from late mount must not appear after clear()")
    }

    func testDispatchErrorCollapsesViaOnSessionError() {
        let controller = CanvasSessionController()
        let fake = GatedScripting()
        let sink = LocalEffectSink()
        controller.onSessionError = { sink.errors.append($0) }

        struct TestError: Error {}
        fake.error = TestError()

        let session = CanvasSession(header: CanvasHeader(title: "Err"), input: "e", preferredSize: nil, scripting: fake, isAsync: false, tree: textTree("E"))
        controller.replace(with: session)

        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "btn"))
        fake.release()
        pump()

        XCTAssertNil(controller.session, "dispatch error clears session")
        XCTAssertEqual(sink.errors.count, 1)
    }

    func testEffectsFromDispatchNeverDismiss() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        controller.armCanvasForTesting(tree: textTree("Canvas"), header: CanvasHeader(title: "Test"))
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertTrue(controller.isVisible)

        controller.canvasSessionController.onEffects?([.paste("x")])
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content, "canvas should remain open after effect delivery")
        XCTAssertTrue(controller.isVisible, "panel must remain visible")
    }

    func testMountPreferredSizeFallsBackToRequest() {
        let controller = CanvasSessionController()
        let fake = GatedScripting()
        let requested = CanvasSize(width: 300, height: 180)
        fake.mountResult = CanvasMountResult(state: CanvasSessionState(), tree: textTree("Fallback"), preferredSize: nil)
        controller.mount(CanvasMountRequest(input: "in", preferredSize: requested), scripting: fake, header: CanvasHeader(title: "Size"))
        pump()
        fake.release()
        pump()
        XCTAssertEqual(controller.session?.preferredSize, requested, "request-declared size used when the script declares none")

        let controller2 = CanvasSessionController()
        let fake2 = GatedScripting()
        fake2.mountResult = CanvasMountResult(state: CanvasSessionState(), tree: textTree("Declared"), preferredSize: CanvasSize(width: 420, height: 260))
        controller2.mount(CanvasMountRequest(input: "in", preferredSize: requested), scripting: fake2, header: CanvasHeader(title: "Size"))
        pump()
        fake2.release()
        pump()
        XCTAssertEqual(controller2.session?.preferredSize, CanvasSize(width: 420, height: 260), "engine-declared size wins over the request value")
    }

    func testDispatchStatusRoutedToOnStatus() {
        let controller = CanvasSessionController()
        let fake = GatedScripting()
        var received: [StatusFeedback] = []
        controller.onStatus = { received.append($0) }

        let session = CanvasSession(header: CanvasHeader(title: "S"), input: "s", preferredSize: nil, scripting: fake, isAsync: false, tree: textTree("S"))
        controller.replace(with: session)

        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("S2"), status: StatusFeedback(message: "Saved", style: .success))]
        controller.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "btn"))
        pump()
        fake.release()
        pump()

        XCTAssertEqual(received, [StatusFeedback(message: "Saved", style: .success)])
    }

    // MARK: - Step 2: Integration tests (controller + panel)

    func testScriptedDispatchReRendersPanelAndKeepsCanvasOpen() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        let fake = GatedScripting()
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(["count": .number(1)]), tree: textTree("Count: 1", id: "cnt"))]

        controller.armCanvasForTesting(
            tree: textTree("Count: 0", id: "cnt"),
            header: CanvasHeader(title: "Counter"),
            scripting: fake,
            state: CanvasSessionState(["count": .number(0)])
        )
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content)

        controller.canvasSessionController.dispatch(CanvasEvent(kind: .tap, handler: "inc", targetID: "cnt"))
        pump()
        fake.release()
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content, "panel remains open")
        XCTAssertEqual(controller.canvasSessionController.session?.tree, textTree("Count: 1", id: "cnt"))
    }

    func testCanvasEffectKeepsCanvasOpen() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        let fake = GatedScripting()
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("Done"), effects: [.paste("x")])]

        controller.armCanvasForTesting(
            tree: textTree("Start"),
            header: CanvasHeader(title: "EffectTest"),
            scripting: fake
        )
        pump()

        controller.canvasSessionController.dispatch(CanvasEvent(kind: .tap, handler: "doPaste", targetID: "btn"))
        fake.release()
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertTrue(controller.isVisible)
    }

    func testEscCollapsesAndClearsSession() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        controller.armCanvasForTesting(
            tree: .textField(CanvasTextFieldProps(id: "field", value: "text", onSubmit: nil)),
            header: CanvasHeader(title: "Form")
        )
        let panel = try visiblePanel()
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertNotNil(controller.canvasSessionController.session)

        let escEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        panel.sendEvent(escEvent)
        pump()

        XCTAssertEqual(controller.modeStore.mode, .actions, "Esc must collapse content mode back to actions")
        XCTAssertNil(controller.canvasSessionController.session, "Esc must clear the session")
    }

    func testMountErrorCollapsesAndShowsErrorBanner() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        struct MountFailError: LocalizedError {
            var errorDescription: String? { "Mount failed" }
        }

        let fake = GatedScripting()
        fake.error = MountFailError()

        controller.canvasSessionController.mount(
            CanvasMountRequest(input: "sel"),
            scripting: fake,
            header: CanvasHeader(title: "Fail")
        )
        fake.release()
        pump()

        XCTAssertEqual(controller.modeStore.mode, .actions, "mount error collapses mode back to actions")
        XCTAssertNil(controller.canvasSessionController.session, "mount error clears session")
        XCTAssertEqual(controller.modeStore.statusBanner?.style, .error)
        XCTAssertEqual(controller.modeStore.statusBanner?.message, "Mount failed")
    }

    func testStatusWhileCanvasOpenSurfacesAfterCollapse() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        controller.armCanvasForTesting(tree: textTree("Canvas"), header: CanvasHeader(title: "Title"))
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertNil(controller.modeStore.statusBanner)

        controller.handleActionResult(.showStatus(StatusFeedback(message: "Queued Status", style: .info)))
        XCTAssertNil(controller.modeStore.statusBanner, "status banner must not show while canvas is open")

        controller.exitContent()
        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertEqual(controller.modeStore.statusBanner?.message, "Queued Status", "queued status surfaces after canvas collapse")
    }

    func testHideClearsSessionAndCancelsInflight() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        let fake = GatedScripting()
        fake.dispatchResults = [CanvasDispatchResult(state: CanvasSessionState(), tree: textTree("LateTree"))]

        controller.armCanvasForTesting(
            tree: textTree("Init"),
            header: CanvasHeader(title: "HideTest"),
            scripting: fake
        )
        pump()

        controller.canvasSessionController.dispatch(CanvasEvent(kind: .tap, handler: "h", targetID: "btn"))
        pump()

        controller.hide()
        XCTAssertNil(controller.modeStore.content)
        XCTAssertNil(controller.canvasSessionController.session)
        XCTAssertFalse(controller.isVisible)

        fake.release()
        pump()

        XCTAssertNil(controller.modeStore.content, "late result after hide() must be ignored")
        XCTAssertNil(controller.canvasSessionController.session)
    }
}

@MainActor
private final class LocalEffectSink {
    var effects: [[CanvasEffect]] = []
    var errors: [Error] = []
}
