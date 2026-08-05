import XCTest
@testable import Core
@testable import OpenClip

final class ContextualFilteringTests: XCTestCase {
    
    func createMockContext(with text: String) -> ActionContext {
        let selection = SelectionContext(text: text, sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        return ActionContext(selection: selection, modifiers: [])
    }
    
    @MainActor
    func testOpenURLActionContextualFiltering() {
        let action = OpenURLAction()
        
        let validContext = createMockContext(with: "https://apple.com")
        XCTAssertTrue(action.isEnabled(for: validContext))
        
        let plainTextContext = createMockContext(with: "hello world")
        XCTAssertFalse(action.isEnabled(for: plainTextContext))
        
        let paddedContext = createMockContext(with: "  https://apple.com  ")
        XCTAssertTrue(action.isEnabled(for: paddedContext))
    }
    
    @MainActor
    func testSearchActionContextualFiltering() {
        let action = SearchAction()
        
        let urlContext = createMockContext(with: "https://google.com")
        XCTAssertFalse(action.isEnabled(for: urlContext))
        
        let plainTextContext = createMockContext(with: "macOS swift development")
        XCTAssertTrue(action.isEnabled(for: plainTextContext))
        
        let paddedUrlContext = createMockContext(with: "  https://google.com  ")
        XCTAssertFalse(action.isEnabled(for: paddedUrlContext))
        
        let emptyContext = createMockContext(with: "   ")
        XCTAssertFalse(action.isEnabled(for: emptyContext))
    }
}
