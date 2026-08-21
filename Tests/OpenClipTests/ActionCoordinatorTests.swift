import XCTest
@testable import Core

final class ActionCoordinatorTests: XCTestCase {
    private var tempDir: URL!
    private var tempExtensionsDir: URL!
    private var tempRulesURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ActionCoordinatorTests-\(UUID().uuidString)")
        tempExtensionsDir = tempDir.appendingPathComponent("extensions")
        tempRulesURL = tempDir.appendingPathComponent("rules.json")
        try FileManager.default.createDirectory(at: tempExtensionsDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    @MainActor
    func testActionCoordinatorResolvesActionsForContext() async {
        let coordinator = ActionCoordinator.shared
        await coordinator.loadInitialState(
            extensionsDirectory: tempExtensionsDir,
            rulesURL: tempRulesURL
        )
        
        let app = AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        let selection = SelectionContext(
            text: "Hello World",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection, modifiers: [])
        
        let resolved = coordinator.resolveActions(for: context)
        XCTAssertFalse(resolved.isEmpty, "ActionCoordinator should resolve active actions for context")
    }
    
    @MainActor
    func testRegisteringCustomActionUpdatesActionsList() async {
        let coordinator = ActionCoordinator.shared
        struct MockAction: Action {
            let id = "test.mock"
            let title = "Mock"
            let icon = ActionIcon.symbol("star")
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .none }
        }
        
        coordinator.register(action: MockAction())
        XCTAssertTrue(coordinator.actions.contains(where: { $0.id == "test.mock" }))
    }
}
