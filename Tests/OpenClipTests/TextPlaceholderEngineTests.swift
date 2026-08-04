import XCTest
@testable import Core

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

private extension ActionContext {
    init(selectedText: String, match: ActionMatchInfo? = nil) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        self.init(selection: selection, modifiers: [], match: match)
    }
}

final class TextPlaceholderEngineTests: XCTestCase {
    func testAllPlaceholderVariantsAreSubstituted() {
        let input = "hello world"
        let context = ActionContext(selectedText: input)
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={text}", context: context, urlEncode: true), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={query}", context: context, urlEncode: true), "https://google.com/search?q=hello%20world")
    }

    func testUnencodedPlaceholderSubstitution() {
        let input = "hello world"
        let context = ActionContext(selectedText: input)
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {text}", context: context, urlEncode: false), "echo hello world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {query}", context: context, urlEncode: false), "echo hello world")
    }

    func testMatchedCaptureAndBundlePlaceholders() {
        let match = ActionMatchInfo(text: "contact a@b.com now", matchedText: "a@b.com", captures: ["a", "b.com"], sourceBundleID: "com.test")
        let context = ActionContext(selectedText: "contact a@b.com now", match: match)
        let url = TextPlaceholderEngine.replacePlaceholders(
            in: "https://example.com/{matched}/{capture1}/{2}/{bundleID}",
            context: context,
            urlEncode: true
        )
        XCTAssertEqual(url, "https://example.com/a%40b.com/a/b.com/com.test")
    }

    func testLegacyBareOverloadStillSubstitutesTextAndQuery() {
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={text}", with: "hello world"), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {query}", with: "hello world", urlEncode: false), "echo hello world")
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
