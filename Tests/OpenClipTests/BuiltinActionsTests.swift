import XCTest
@testable import Core
@testable import OpenClip

struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

final class BuiltinActionsTests: XCTestCase {
    
    func createMockContext(with text: String) -> ActionContext {
        let selection = SelectionContext(text: text, sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date())
        return ActionContext(selection: selection, modifiers: [])
    }
    
    @MainActor
    func testCopyAction() async throws {
        let action = CopyAction()
        let context = createMockContext(with: "test string")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .copy(let text) = result {
            XCTAssertEqual(text, "test string")
        } else {
            XCTFail("Expected .copy result")
        }
    }
    
    @MainActor
    func testPasteAction() async throws {
        let action = PasteAction()
        let context = createMockContext(with: "test string")
        
        // PasteAction isEnabled checks if there's a string on the pasteboard.
        // We just test perform logic here.
        let result = try await action.perform(context)
        if case .simulatePaste = result {
            // Success
        } else {
            XCTFail("Expected .simulatePaste result")
        }
    }
    
    @MainActor
    func testSearchAction() async throws {
        let action = SearchAction()
        let context = createMockContext(with: "test search")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://www.google.com/search?q=test%20search")
        } else {
            XCTFail("Expected .openURL result")
        }
    }
    
    @MainActor
    func testOpenURLAction() async throws {
        let action = OpenURLAction()
        
        // Test valid URL
        let validContext = createMockContext(with: "Check out https://apple.com for more info")
        XCTAssertTrue(action.isEnabled(for: validContext))
        
        let validResult = try await action.perform(validContext)
        if case .openURL(let url) = validResult {
            XCTAssertEqual(url.absoluteString, "https://apple.com")
        } else {
            XCTFail("Expected .openURL result for valid URL")
        }
        
        // Test invalid URL
        let invalidContext = createMockContext(with: "No URL here")
        XCTAssertFalse(action.isEnabled(for: invalidContext))
        
        let invalidResult = try await action.perform(invalidContext)
        if case .failure(_) = invalidResult {
            // Success
        } else {
            XCTFail("Expected .failure result for invalid URL")
        }
    }
    
    @MainActor
    func testCutAction() async throws {
        let action = CutAction()
        let context = createMockContext(with: "test cut")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .cut(let text) = result {
            XCTAssertEqual(text, "test cut")
        } else {
            XCTFail("Expected .cut result")
        }
    }
    
    @MainActor
    func testServicesAction() async throws {
        let action = ServicesAction()
        let context = createMockContext(with: "test services")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .showServices(let text) = result {
            XCTAssertEqual(text, "test services")
        } else {
            XCTFail("Expected .showServices result")
        }
    }
}
