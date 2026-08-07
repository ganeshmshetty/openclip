import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionCoordinatorStartupTests: XCTestCase {
    let packageID = "com.custom.startup.test"
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        ExtensionManager.shared.actionFactory = DefaultActionFactory()
    }
    
    override func tearDown() async throws {
        ActionRegistry.shared.unregister(actionID: packageID)
        ExtensionManager.shared.actionFactory = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
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
        // into a temp extensions directory (exactly what the Add sheet writes, just isolated from
        // the real ~/.openclip/extensions) and let the coordinator's startup scan pick it up.
        try? CustomActionManifestWriter.write(action: action, to: tempDir)
        
        // Empty rules file so loadInitialState never reads the real ~/.openclip/rules.json.
        let rulesURL = tempDir.appendingPathComponent("rules.json")
        try? #"{"rules":[]}"#.data(using: .utf8)?.write(to: rulesURL)
        
        // Clear registry to simulate startup state before coordinator loadInitialState
        ActionRegistry.shared.unregister(actionID: packageID)
        XCTAssertFalse(ActionRegistry.shared.actions.contains(where: { $0.id == packageID }))

        let coordinator = ActionCoordinator()
        await coordinator.loadInitialState(extensionsDirectory: tempDir, rulesURL: rulesURL)
        
        let registeredActions = ActionRegistry.shared.actions
        XCTAssertTrue(registeredActions.contains(where: { $0.id == packageID }))
    }
}
