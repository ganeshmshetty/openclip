import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class CompletionActionTests: XCTestCase {
    @MainActor
    func testCompletionActionSmartTrigger() async throws {
        let action = CompletionAction()
        let app = AppIdentity(NSRunningApplication.current)
        
        // Single incomplete word (e.g. "comple") -> Should have completions
        let partialContext = ActionContext(
            selection: SelectionContext(text: "comple", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let isEnabled = action.isEnabled(for: partialContext)
        XCTAssertTrue(isEnabled, "CompletionAction should be enabled for partial word 'comple'")
        
        // Math context -> Disabled
        let mathContext = ActionContext(
            selection: SelectionContext(text: "12 + 4.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: mathContext), "CompletionAction should be disabled for math")
        
        // URL context -> Disabled
        let urlContext = ActionContext(
            selection: SelectionContext(text: "https://apple.com", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: urlContext), "CompletionAction should be disabled for URLs")
    }
    
    @MainActor
    func testFetchCompletionsUsesTheBestFittingLanguage() async throws {
        let action = CompletionAction(spellChecker: StubTextSpellChecker(
            languages: ["en", "sv"],
            reports: [
                SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey"]),
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: ["hejda"], guesses: [])
            ]
        ))
        XCTAssertEqual(action.fetchCompletions(for: "hej"), ["hejda"])
    }

    @MainActor
    func testFetchCompletions() async throws {
        let action = CompletionAction()
        let completions = action.fetchCompletions(for: "comple")
        XCTAssertFalse(completions.isEmpty, "fetchCompletions should return completion candidates for 'comple'")
        XCTAssertTrue(completions.contains(where: { $0.lowercased().hasPrefix("comple") }), "Completions should contain words starting with 'comple'")
    }
}
