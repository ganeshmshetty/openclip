import XCTest
@testable import Core

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

final class TextPlaceholderEngineTests: XCTestCase {
    func testAllPlaceholderVariantsAreSubstituted() {
        let input = "hello world"
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={text}", with: input), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={query}", with: input), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={popclip text}", with: input), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={openclip text}", with: input), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q=***", with: input), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q=%@", with: input), "https://google.com/search?q=hello%20world")
    }

    func testUnencodedPlaceholderSubstitution() {
        let input = "hello world"
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {text}", with: input, urlEncode: false), "echo hello world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {query}", with: input, urlEncode: false), "echo hello world")
    }

    @MainActor
    func testURLTemplateActionUsesPlaceholderEngine() async throws {
        let action = URLTemplateAction(
            id: "test.search",
            title: "Search",
            icon: .symbol("magnifyingglass"),
            urlTemplate: "https://example.com/search?q={query}"
        )
        let mockApp = MockApp(bundleIdentifier: "com.test", localizedName: "Test")
        let selection = SelectionContext(text: "swift testing", sourceApp: mockApp, cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        
        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://example.com/search?q=swift%20testing")
        } else {
            XCTFail("Expected .openURL result")
        }
    }
}
