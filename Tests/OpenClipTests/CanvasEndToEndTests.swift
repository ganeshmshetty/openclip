// CanvasEndToEndTests.swift
// OpenClipTests
//
// End-to-end canvas tests: drive the real JS canvas producer (manifest `type: "canvas"` →
// JavaScriptCanvasAction → JavaScriptCanvasEngine) through the ActionCoordinator. A fixture
// extension is loaded through TestIsolation.reset() + the ActionCoordinator real constructor +
// loadInitialState(extensionsDirectory:rulesURL:) — never the real ~/.openclip.
//
// NOTE: earlier panel-mounting tests (real PopupWindowController + NSPanel visibility/key events
// + the JS engine) proved inherently flaky in this environment — the mount condition intermittently
// never armed content mode even with generous 5s polling, and `orderFront` panels sporadically
// never registered in NSApp.windows. The remaining test asserts the canvas action contract through
// the coordinator/engine alone, with no window-server dependency.

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

    // MARK: - Tests

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
}
