import XCTest
@testable import Core

struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

struct MockAction: Action {
    let id: String
    let title = "Mock"
    let icon = ActionIcon.symbol("star")
    let shouldBeEnabled: Bool
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool {
        return shouldBeEnabled
    }
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult {
        return .success
    }
}

final class ActionRegistryTests: XCTestCase {
    @MainActor
    func testActionRegistrationAndAvailability() {
        let registry = ActionRegistry.shared
        
        let action1 = MockAction(id: "mock.1", shouldBeEnabled: true)
        let action2 = MockAction(id: "mock.2", shouldBeEnabled: false)
        
        let initialCount = registry.actions.count
        registry.register(builtIns: [action1, action2])
        
        XCTAssertEqual(registry.actions.count, initialCount + 2)
        
        let selection = SelectionContext(text: "test", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date())
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertTrue(available.contains(where: { $0.id == "mock.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "mock.2" }))
    }
    
    func testActionContext() {
        let selection = SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date())
        let context = ActionContext(selection: selection, modifiers: [.shift])
        
        XCTAssertEqual(context.selection.text, "hello")
        XCTAssertEqual(context.modifiers, [.shift])
    }
}
