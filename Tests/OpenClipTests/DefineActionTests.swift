import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class DefineActionTests: XCTestCase {
    @MainActor
    func testDefineActionSmartTrigger() async throws {
        let action = DefineAction()
        let app = NSRunningApplication.current
        
        // Single word -> Enabled
        let wordContext = ActionContext(
            selection: SelectionContext(text: "serendipity", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: wordContext), "DefineAction should be enabled for single words")
        
        // Short phrase (2 words) -> Enabled
        let phraseContext = ActionContext(
            selection: SelectionContext(text: "quantum physics", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: phraseContext), "DefineAction should be enabled for short phrases")
        
        // Math formula -> Disabled
        let mathContext = ActionContext(
            selection: SelectionContext(text: "12 + 4.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: mathContext), "DefineAction should be disabled for math expressions")
        
        // URL -> Disabled
        let urlContext = ActionContext(
            selection: SelectionContext(text: "https://apple.com", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: urlContext), "DefineAction should be disabled for URLs")
        
        // Long paragraph (>40 chars or >3 words) -> Disabled
        let paragraphContext = ActionContext(
            selection: SelectionContext(text: "This is a very long text paragraph that exceeds the maximum length threshold.", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: paragraphContext), "DefineAction should be disabled for long paragraphs")
    }
    
    @MainActor
    func testDefineActionExecution() async throws {
        let action = DefineAction()
        let app = NSRunningApplication.current
        let context = ActionContext(
            selection: SelectionContext(text: "epiphany", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.scheme, "dict")
            XCTAssertTrue(url.absoluteString.contains("epiphany"))
        } else {
            XCTFail("Expected openURL with dict:// scheme for DefineAction")
        }
    }
}
