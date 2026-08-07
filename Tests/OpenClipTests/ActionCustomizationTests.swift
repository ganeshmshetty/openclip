import XCTest
@testable import OpenClip
@testable import Core

private struct CustomizationMockAction: Action {
    let id: String = "mock.test"
    let title: String = "Default Title"
    let icon: ActionIcon = .symbol("star")
    
    func isEnabled(for context: ActionContext) -> Bool { true }
    func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

@MainActor
final class ActionCustomizationTests: XCTestCase {
    func testDefaultTitleAndIconFallback() {
        let manager = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let action = CustomizationMockAction()
        XCTAssertEqual(action.displayTitle(using: manager), "Default Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("star"))
    }
    
    func testCustomTitleAndIconOverrides() {
        let manager = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let action = CustomizationMockAction()
        
        // Set custom title and custom symbol icon
        manager.setOverride(for: "mock.test", title: "Custom Title", symbol: "heart.fill", text: nil)
        XCTAssertEqual(action.displayTitle(using: manager), "Custom Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("heart.fill"))
        
        // Set custom text/emoji icon
        manager.setOverride(for: "mock.test", title: "Custom Title", symbol: nil, text: "❤️")
        XCTAssertEqual(action.displayTitle(using: manager), "Custom Title")
        XCTAssertEqual(action.displayIcon(using: manager), .text("❤️"))
        
        // Reset override
        manager.resetOverride(for: "mock.test")
        XCTAssertEqual(action.displayTitle(using: manager), "Default Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("star"))
    }
}
