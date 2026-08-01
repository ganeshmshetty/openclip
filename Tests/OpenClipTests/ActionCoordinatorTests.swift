import XCTest
@testable import Core

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

@MainActor
final class ActionCoordinatorTests: XCTestCase {
    func testActionCoordinatorResolvesActionsForContext() async {
        let coordinator = ActionCoordinator.shared
        await coordinator.loadInitialState()
        
        let app = MockApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
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
}
