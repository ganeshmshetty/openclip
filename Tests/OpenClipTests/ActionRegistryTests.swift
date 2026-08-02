import XCTest
@testable import Core

fileprivate struct MockApp: AppIdentifying {
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
        
        let selection = SelectionContext(text: "test", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertTrue(available.contains(where: { $0.id == "mock.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "mock.2" }))
    }
    
    func testActionContext() {
        let selection = SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: .shift)
        
        XCTAssertEqual(context.selection.text, "hello")
        XCTAssertEqual(context.modifiers, .shift)
    }
    
    @MainActor
    func testDenyFormattingPolicyFiltersFormattingActions() {
        let registry = ActionRegistry.shared
        
        struct MockFormattingAction: Action {
            let id = "mock.formatting"
            let title = "Format"
            let icon = ActionIcon.symbol("star")
            var isFormatting: Bool { true }
            
            @MainActor
            func isEnabled(for context: ActionContext) -> Bool { return true }
            @MainActor
            func perform(_ context: ActionContext) async throws -> ActionResult { return .success }
        }
        
        let formatAction = MockFormattingAction()
        registry.register(action: formatAction)
        
        let denyPolicy = AppPolicyContext(denyFormatting: true, denyProbe: false, denyPreprobe: false, grabPasteboard: false, assumePaste: false)
        let denySelection = SelectionContext(text: "test", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: denyPolicy)
        let denyContext = ActionContext(selection: denySelection, modifiers: [])
        
        let availableWithDeny = registry.availableActions(for: denyContext)
        XCTAssertFalse(availableWithDeny.contains(where: { $0.id == "mock.formatting" }), "Formatting action should be filtered out when denyFormatting is true")
        
        let allowSelection = SelectionContext(text: "test", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let allowContext = ActionContext(selection: allowSelection, modifiers: [])
        
        let availableWithAllow = registry.availableActions(for: allowContext)
        XCTAssertTrue(availableWithAllow.contains(where: { $0.id == "mock.formatting" }), "Formatting action should be included when denyFormatting is false")
    }
    
    @MainActor
    func testDisabledActionsAreFiltered() {
        let registry = ActionRegistry.shared
        
        let action = MockAction(id: "mock.disabled.test", shouldBeEnabled: true)
        registry.register(action: action)
        
        let oldDisabled = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey)
        UserDefaults.standard.set(["mock.disabled.test"], forKey: Constants.disabledActionIDsKey)
        defer {
            if let oldDisabled {
                UserDefaults.standard.set(oldDisabled, forKey: Constants.disabledActionIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.disabledActionIDsKey)
            }
        }
        
        let selection = SelectionContext(text: "test", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.availableActions(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == "mock.disabled.test" }))
    }
}
