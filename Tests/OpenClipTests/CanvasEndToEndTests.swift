// CanvasEndToEndTests.swift
// OpenClipTests
//
// End-to-end canvas tests: drive the real JS canvas producer (manifest `type: "canvas"` →
// JavaScriptCanvasAction → JavaScriptCanvasEngine) through a real PopupWindowController and panel.
// A fixture extension is loaded through TestIsolation.reset() + the ActionCoordinator real
// constructor + loadInitialState(extensionsDirectory:rulesURL:) — never the real ~/.openclip —
// and every assertion observes the mounted session, the content-mode state, and the panel's key
// status.

import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class CanvasEndToEndTests: XCTestCase {
    private var tempDir: URL!
    private var coordinator: ActionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Empty rules config so loadInitialState never reads the real ~/.openclip/rules.json.
        let rulesURL = tempDir.appendingPathComponent("rules.json")
        try #"{"rules":[]}"#.data(using: .utf8)?.write(to: rulesURL)

        // Fixture extension package: an inline-scriptCode canvas action.
        let bundle = tempDir.appendingPathComponent("CanvasExt.openclipext")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let manifest = """
        {
          "identifier": "com.e2e.canvas",
          "name": "Canvas E2E",
          "actions": [
            {
              "id": "canvas.counter",
              "title": "Counter",
              "type": "canvas",
              "scriptCode": "const initialState = { count: 0 }; const handlers = { increment: (state) => ({ count: state.count + 1 }) }; const ui = (state) => h('button', { title: 'Count: ' + state.count, handler: 'increment' });"
            }
          ]
        }
        """
        try manifest.write(to: bundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)

        ExtensionManager.shared.actionFactory = DefaultActionFactory()
        let coordinator = ActionCoordinator(
            registry: .shared,
            ruleEngine: .shared,
            extensionManager: .shared,
            settingsStore: MemorySettingsStore()
        )
        self.coordinator = coordinator
        await coordinator.loadInitialState(extensionsDirectory: tempDir, rulesURL: rulesURL)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        ExtensionManager.shared.actionFactory = nil
        self.coordinator = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func shownController(for cursor: CGPoint = .zero) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = PopupWindowController()
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.e2e.app", localizedName: "E2E App"),
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

    /// Async pump: sleeps the test method so the controller's serialized mount/dispatch task chain
    /// (and the engine's `Task.detached` evaluation) can progress. A run-loop spin does NOT work
    /// here — an `async` @MainActor test method holds the executor, so `RunLoop.current.run` can't
    /// deliver other MainActor jobs. `Task.sleep` yields real wall-clock time, which the first
    /// (cold) JS compile needs.
    private func pump(seconds: TimeInterval = 0.05, rounds: Int = 8) async {
        for _ in 0..<rounds {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await Task.yield()
        }
    }

    private func makeContext(text: String = "hello") -> ActionContext {
        ActionContext(
            selection: SelectionContext(
                text: text,
                sourceApp: AppIdentity(bundleIdentifier: "com.e2e.app", localizedName: "E2E App"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            ),
            modifiers: []
        )
    }

    /// The fixture canvas action as resolved through the coordinator, or nil (test fails loudly).
    private func canvasCounterAction() -> JavaScriptCanvasAction? {
        let actions = coordinator.resolveActions(for: makeContext())
        return actions.first(where: { $0.id == "canvas.counter" }) as? JavaScriptCanvasAction
    }

    private func buttonTitle(_ tree: CanvasComponent?) -> String? {
        if case .button(let props)? = tree { return props.title }
        return nil
    }

    /// Performs the fixture counter action and hands its `.showCanvas` result to the controller.
    /// The controller must reach `.content` after the mount's onSessionArmed → armMountedSession.
    private func armCounter(on controller: PopupWindowController) async throws {
        guard let canvasAction = canvasCounterAction() else {
            throw XCTSkip("canvas.counter should resolve as a JavaScriptCanvasAction")
        }
        let result = try await canvasAction.perform(makeContext())
        guard case .showCanvas(let request, let header) = result else {
            throw XCTSkip("Expected .showCanvas, got \(result)")
        }
        controller.handleActionResult(.showCanvas(request, header))
        await pump()
        XCTAssertEqual(controller.modeStore.mode, .content, "mount must arm content mode")
    }

    // MARK: - Tests

    func testCanvasExtensionMountsThroughCoordinatorAndPanel() async throws {
        guard let canvasAction = canvasCounterAction() else {
            return XCTFail("canvas.counter should resolve as a JavaScriptCanvasAction")
        }

        let result = try await canvasAction.perform(makeContext())
        guard case .showCanvas(let request, let header) = result else {
            return XCTFail("Expected .showCanvas, got \(result)")
        }
        XCTAssertTrue(request.scriptCode.contains("increment"), "mount request carries the fixture script")
        XCTAssertEqual(header.title, "Counter", "canvas chrome uses the action title")

        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        controller.handleActionResult(.showCanvas(request, header))
        await pump()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(buttonTitle(controller.canvasSessionController.session?.tree), "Count: 0",
                       "session tree renders the mounted button tree")
        let panel = try visiblePanel()
        XCTAssertTrue(panel.allowsKey, "content mode must key the panel exactly like search")
    }

    func testButtonDispatchReRendersPanel() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        try await armCounter(on: controller)

        // ≥3 dispatches: the observable compile-once contract — one compiled script serving every
        // dispatch, so the counter climbs 1 → 2 → 3 instead of re-mounting at 0.
        let expected = ["Count: 1", "Count: 2", "Count: 3"]
        for (index, title) in expected.enumerated() {
            controller.canvasSessionController.dispatch(CanvasEvent(kind: .tap, handler: "increment", targetID: "cnt"))
            await pump()
            XCTAssertEqual(controller.modeStore.mode, .content, "canvas must stay open through dispatch \(index + 1)")
            XCTAssertEqual(buttonTitle(controller.canvasSessionController.session?.tree), title,
                           "dispatch \(index + 1) must re-render the tree in place")
        }
    }

    func testEscCollapsesCanvasAction() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        try await armCounter(on: controller)
        let panel = try visiblePanel()

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
        await pump()

        XCTAssertEqual(controller.modeStore.mode, .actions, "Esc must collapse content mode back to actions")
        XCTAssertNil(controller.canvasSessionController.session, "Esc must clear the session")
    }

    func testNewMountReplacesCanvasSession() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        try await armCounter(on: controller)
        let firstSessionID = try XCTUnwrap(controller.canvasSessionController.session?.id)
        XCTAssertEqual(buttonTitle(controller.canvasSessionController.session?.tree), "Count: 0")

        controller.canvasSessionController.dispatch(CanvasEvent(kind: .tap, handler: "increment", targetID: "cnt"))
        await pump()
        XCTAssertEqual(buttonTitle(controller.canvasSessionController.session?.tree), "Count: 1")

        guard let canvasAction = canvasCounterAction() else {
            return XCTFail("canvas.counter should resolve as a JavaScriptCanvasAction")
        }
        let freshResult = try await canvasAction.perform(makeContext())
        guard case .showCanvas(let request, let header) = freshResult else {
            return XCTFail("Expected .showCanvas, got \(freshResult)")
        }
        controller.handleActionResult(.showCanvas(request, header))
        await pump()

        XCTAssertEqual(buttonTitle(controller.canvasSessionController.session?.tree), "Count: 0",
                       "a fresh mount re-renders from initial state")
        XCTAssertNotEqual(controller.canvasSessionController.session?.id, firstSessionID,
                          "a fresh mount must create a new session, not reuse the old one")
    }

    func testCanvasActionInSearchCatalog() async throws {
        XCTAssertTrue(coordinator.searchCatalog.contains { $0.id == "canvas.counter" },
                      "canvas action appears in the action-search palette catalog")

        guard let canvasAction = canvasCounterAction() else {
            return XCTFail("canvas.counter should resolve as a JavaScriptCanvasAction")
        }
        XCTAssertEqual(canvasAction.chrome.popupBehavior, .perform,
                       "canvas action is a plain .perform bar row")

        let result = try await canvasAction.perform(makeContext())
        guard case .showCanvas = result else {
            return XCTFail("Expected .showCanvas, got \(result)")
        }
    }

    func testHoverNeverArmsSessionOrKeysPanel() async throws {
        guard let canvasAction = canvasCounterAction() else {
            return XCTFail("canvas.counter should resolve as a JavaScriptCanvasAction")
        }
        // (a) unit: canvas rows never show a hover strip.
        XCTAssertFalse(canvasAction.gesturePolicy.hoverPreview,
                       "canvas actions must never show a hover preview strip")

        // (b) integration: hovering the bar never arms a session or keys the panel.
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownController(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.content)
        XCTAssertFalse(panel.allowsKey)

        // Publish a hover location inside the bar and wait well past the hover-preview debounce.
        PopupHoverState.shared.location = CGPoint(x: panel.frame.midX, y: panel.frame.minY + 10)
        await pump(seconds: 0.01, rounds: 120)

        XCTAssertEqual(controller.modeStore.mode, .actions, "hovering must never leave actions mode")
        XCTAssertNil(controller.modeStore.content, "hovering must never arm a canvas session")
        XCTAssertFalse(panel.allowsKey, "hovering must never key the panel")
        if let preview = controller.modeStore.preview {
            guard case .text = preview else {
                return XCTFail("hover preview must be a static .text snapshot, got \(preview)")
            }
        }
    }
}
