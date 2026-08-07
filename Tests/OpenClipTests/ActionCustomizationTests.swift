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
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        ActionCustomizationManager.shared.resetOverride(for: "mock.test")
    }
    
    override func tearDown() {
        ActionCustomizationManager.shared.resetOverride(for: "mock.test")
        super.tearDown()
    }
    
    func testDefaultTitleAndIconFallback() {
        let action = CustomizationMockAction()
        XCTAssertEqual(action.displayTitle, "Default Title")
        XCTAssertEqual(action.displayIcon, .symbol("star"))
    }
    
    func testCustomTitleAndIconOverrides() {
        let action = CustomizationMockAction()
        
        // Set custom title and custom symbol icon
        ActionCustomizationManager.shared.setOverride(for: "mock.test", title: "Custom Title", symbol: "heart.fill", text: nil)
        XCTAssertEqual(action.displayTitle, "Custom Title")
        XCTAssertEqual(action.displayIcon, .symbol("heart.fill"))
        
        // Set custom text/emoji icon
        ActionCustomizationManager.shared.setOverride(for: "mock.test", title: "Custom Title", symbol: nil, text: "❤️")
        XCTAssertEqual(action.displayTitle, "Custom Title")
        XCTAssertEqual(action.displayIcon, .text("❤️"))
        
        // Reset override
        ActionCustomizationManager.shared.resetOverride(for: "mock.test")
        XCTAssertEqual(action.displayTitle, "Default Title")
        XCTAssertEqual(action.displayIcon, .symbol("star"))
    }
}
