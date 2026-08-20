import XCTest
@testable import Core

private extension ActionContext {
    init(selectedText: String, match: ActionMatchInfo? = nil) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
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

    func testBareContextSubstitutesTextAndQuery() {
        let context = ActionContext(selectedText: "hello world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "https://google.com/search?q={text}", context: context), "https://google.com/search?q=hello%20world")
        XCTAssertEqual(TextPlaceholderEngine.replacePlaceholders(in: "echo {query}", context: context, urlEncode: false), "echo hello world")
    }

    func testNoCascadingSubstitutions() {
        // Selected text contains literal "{bundleID}" and "{2}"
        let input = "Check {bundleID} and {2} here"
        let match = ActionMatchInfo(text: input, matchedText: input, captures: ["{2}", "real_capture_2"], sourceBundleID: "com.test.app")
        let context = ActionContext(selectedText: input, match: match)

        // {text} should not have its internal "{bundleID}" or "{2}" expanded
        let result = TextPlaceholderEngine.replacePlaceholders(
            in: "echo '{text}' - bundle is '{bundleID}' - captures are '{1}' and '{2}'",
            context: context,
            urlEncode: false
        )
        XCTAssertEqual(
            result,
            "echo 'Check {bundleID} and {2} here' - bundle is 'com.test.app' - captures are '{2}' and 'real_capture_2'"
        )
    }

    func testUnknownPlaceholdersPreserved() {
        let context = ActionContext(selectedText: "hello")
        let result = TextPlaceholderEngine.replacePlaceholders(
            in: "https://example.com/{unknown}?q={text}",
            context: context,
            urlEncode: false
        )
        XCTAssertEqual(result, "https://example.com/{unknown}?q=hello")
    }

    @MainActor
    func testURLTemplateActionUsesPlaceholderEngine() async throws {
        let action = URLTemplateAction(
            id: "test.search",
            title: "Search",
            icon: .symbol("magnifyingglass"),
            urlTemplate: "https://example.com/search?q={query}"
        )
        let mockApp = AppIdentity(bundleIdentifier: "com.test", localizedName: "Test")
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

