import XCTest
@testable import Core

/// Custom-scheme URLs (scratchpad:, goodlinks://) must not be handed to the
/// source browser, or the browser shows an "allow this website to open…" prompt.
final class CustomSchemeBrowserRoutingTests: XCTestCase {
    private func browserContext(_ text: String = "hello") -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    func testHelperOnlyRoutesHTTPToBrowser() {
        XCTAssertEqual(BrowserDetector.browserToOpen(URL(string: "https://example.com")!, sourceBundleIdentifier: "com.apple.Safari"), "com.apple.Safari")
        XCTAssertEqual(BrowserDetector.browserToOpen(URL(string: "HTTP://example.com")!, sourceBundleIdentifier: "com.apple.Safari"), "com.apple.Safari")
        XCTAssertNil(BrowserDetector.browserToOpen(URL(string: "scratchpad:append?text=hi")!, sourceBundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(BrowserDetector.browserToOpen(URL(string: "goodlinks://x-callback-url/save?url=x")!, sourceBundleIdentifier: "com.apple.Safari"))
        XCTAssertNil(BrowserDetector.browserToOpen(URL(string: "https://example.com")!, sourceBundleIdentifier: "com.apple.TextEdit"))
        XCTAssertNil(BrowserDetector.browserToOpen(URL(string: "https://example.com")!, sourceBundleIdentifier: nil))
    }

    func testBraveOriginIsRecognizedAsBrowser() {
        XCTAssertTrue(BrowserDetector.isBrowser(bundleIdentifier: "com.brave.Browser.origin"))
        XCTAssertTrue(BrowserDetector.isBrowser(bundleIdentifier: "com.brave.Browser.origin.beta"))
        XCTAssertEqual(BrowserDetector.browserToOpen(URL(string: "https://example.com")!, sourceBundleIdentifier: "com.brave.Browser.origin"), "com.brave.Browser.origin")
    }

    @MainActor
    func testURLTemplateCustomSchemeFromBrowserOpensViaSystem() async throws {
        let action = URLTemplateAction(id: "test.scratchpad", title: "Scratchpad", icon: .symbol("note"), urlTemplate: "scratchpad:append?text={text}&hide")
        let result = try await action.perform(browserContext())
        guard case .openURL(let url) = result else { return XCTFail("Expected .openURL, got \(result)") }
        XCTAssertEqual(url.scheme, "scratchpad")
    }

    @MainActor
    func testURLTemplateHTTPSFromBrowserStillOpensInBrowser() async throws {
        let action = URLTemplateAction(id: "test.search", title: "Search", icon: .symbol("magnifyingglass"), urlTemplate: "https://example.com/?q={text}")
        let result = try await action.perform(browserContext())
        guard case .openURLInApp(let url, let bundleID) = result else { return XCTFail("Expected .openURLInApp, got \(result)") }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(bundleID, "com.apple.Safari")
    }

    @MainActor
    func testCustomActionCustomSchemeFromBrowserOpensViaSystem() async throws {
        let action = CustomAction(id: "custom.goodlinks", title: "GoodLinks", iconName: "bookmark", type: .openURL(urlTemplate: "goodlinks://x-callback-url/save?url={text}"))
        let result = try await action.perform(browserContext("https://example.com"))
        guard case .openURL(let url) = result else { return XCTFail("Expected .openURL, got \(result)") }
        XCTAssertEqual(url.scheme, "goodlinks")
    }

    @MainActor
    func testCustomActionHTTPSFromBrowserStillOpensInBrowser() async throws {
        let action = CustomAction(id: "custom.search", title: "Search", iconName: "star", type: .openURL(urlTemplate: "https://example.com/?q={text}"))
        let result = try await action.perform(browserContext())
        guard case .openURLInApp(_, let bundleID) = result else { return XCTFail("Expected .openURLInApp, got \(result)") }
        XCTAssertEqual(bundleID, "com.apple.Safari")
    }
}
