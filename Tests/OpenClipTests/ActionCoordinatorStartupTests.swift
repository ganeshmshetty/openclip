import XCTest
@testable import Core

@MainActor
final class ActionCoordinatorStartupTests: XCTestCase {
    override func tearDown() async throws {
        CustomActionManager.shared.delete(customActionID: "user.custom.1")
        ActionRegistry.shared.unregister(actionID: "user.custom.1")
    }

    func testLoadInitialStateLoadsCustomActions() async {
        let customAction = CustomAction(
            id: "user.custom.1",
            title: "My Custom Action",
            iconName: "star",
            type: .textSnippet(template: "hello")
        )
        CustomActionManager.shared.register(customAction: customAction)
        
        // Clear registry to simulate startup state before coordinator loadInitialState
        ActionRegistry.shared.unregister(actionID: "user.custom.1")
        XCTAssertFalse(ActionRegistry.shared.actions.contains(where: { $0.id == "user.custom.1" }))

        let coordinator = ActionCoordinator()
        await coordinator.loadInitialState()
        
        let registeredActions = ActionRegistry.shared.actions
        XCTAssertTrue(registeredActions.contains(where: { $0.id == "user.custom.1" }))
    }
}
