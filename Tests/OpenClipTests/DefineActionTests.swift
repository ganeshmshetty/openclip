import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class DefineActionTests: XCTestCase {
    private let sampleDefinitions: [String: String] = [
        "serendipity": "the occurrence and development of events by chance in a happy or beneficial way.",
        "epiphany": "a moment of sudden and great revelation or realization."
    ]

    private func makeMockLookup() -> @Sendable (String) -> String? {
        let defs = sampleDefinitions
        return { word in
            defs[word.lowercased()]
        }
    }

    @MainActor
    func testDefineActionSmartTrigger() async throws {
        let action = DefineAction(lookup: makeMockLookup())
        let app = AppIdentity(NSRunningApplication.current)
        
        // Single word with definition -> Enabled
        let wordContext = ActionContext(
            selection: SelectionContext(text: "serendipity", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: wordContext), "DefineAction should be enabled for single words with definitions")

        // Single word without definition -> Disabled
        let nonExistentContext = ActionContext(
            selection: SelectionContext(text: "nonexistentword", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: nonExistentContext), "DefineAction should be disabled for words without definitions")
        
        // Multi-word phrase -> Disabled
        let phraseContext = ActionContext(
            selection: SelectionContext(text: "quantum physics", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: phraseContext), "DefineAction should be disabled for multi-word phrases")
        
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
        let action = DefineAction(lookup: makeMockLookup())
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "epiphany", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .text(let definition) = result {
            XCTAssertEqual(definition, "a moment of sudden and great revelation or realization.")
        } else {
            XCTFail("Expected text result for DefineAction, got \(result)")
        }
    }

    @MainActor
    func testDefineActionSecondaryClickReturnsText() async throws {
        let action = DefineAction(lookup: makeMockLookup())
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "epiphany", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: [],
            isSecondaryClick: true
        )

        let result = try await action.perform(context)
        if case .text(let definition) = result {
            XCTAssertEqual(definition, "a moment of sudden and great revelation or realization.")
        } else {
            XCTFail("Expected text result for secondary click on DefineAction, got \(result)")
        }
    }
}
