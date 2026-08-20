import XCTest
@testable import Core

final class ActionCoordinatorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    @MainActor
    func testActionCoordinatorResolvesActionsForContext() async {
        let coordinator = ActionCoordinator.shared
        await coordinator.loadInitialState()
        
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
