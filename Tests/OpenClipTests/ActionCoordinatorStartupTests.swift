import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionCoordinatorStartupTests: XCTestCase {
    let packageID = "com.custom.startup.test"
    
    override func setUp() async throws {
        try await super.setUp()
        ExtensionManager.shared.actionFactory = DefaultActionFactory()
    }
    
    override func tearDown() async throws {
        try? await ExtensionManager.shared.uninstallExtension(actionID: packageID)
        ExtensionManager.shared.actionFactory = nil
        ActionRegistry.shared.unregister(actionID: packageID)
        try await super.tearDown()
    }

    func testLoadInitialStateLoadsManifestPackage() async {
        let action = CustomAction(
            id: packageID,
            title: "Startup Action",
            iconName: "star",
            type: .textSnippet(template: "hello")
        )
        // The manifest is the only canonical action definition: write a single-action package
        // into the real extensions directory, exactly as the Add sheet does, and let the
        // coordinator's startup scan pick it up.
        try? CustomActionManifestWriter.write(action: action)
        
        // Clear registry to simulate startup state before coordinator loadInitialState
        ActionRegistry.shared.unregister(actionID: packageID)
        XCTAssertFalse(ActionRegistry.shared.actions.contains(where: { $0.id == packageID }))

        let coordinator = ActionCoordinator()
        await coordinator.loadInitialState()
        
        let registeredActions = ActionRegistry.shared.actions
        XCTAssertTrue(registeredActions.contains(where: { $0.id == packageID }))
    }
}
