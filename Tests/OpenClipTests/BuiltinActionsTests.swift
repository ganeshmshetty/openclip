import XCTest
@testable import Core
@testable import OpenClip

final class BuiltinActionsTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        await TestIsolation.reset()
    }
    
    func createMockContext(with text: String) -> ActionContext {
        let selection = SelectionContext(text: text, sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        return ActionContext(selection: selection, modifiers: [])
    }
    
    @MainActor
    func testCopyAction() async throws {
        let action = CopyAction()
        let context = createMockContext(with: "test string")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .copySelection(let selection) = result {
            XCTAssertEqual(selection.text, "test string")
        } else {
            XCTFail("Expected native live-selection Copy")
        }
    }

    @MainActor
    func testCopyActionWithRichText() async throws {
        let action = CopyAction()
        let selection = SelectionContext(
            text: "test string",
            sourceApp: AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default,
            html: "<b>test string</b>",
            rtf: "{\\rtf1 test string}"
        )
        let context = ActionContext(selection: selection)
        let result = try await action.perform(context)
        if case .copySelection(let copiedSelection) = result {
            XCTAssertEqual(copiedSelection.text, "test string")
            XCTAssertEqual(copiedSelection.html, "<b>test string</b>")
        } else {
            XCTFail("Even captured rich content should use the source application's native Copy")
        }
    }

    @MainActor
    func testOCRCopyUsesRecognizedTextWithoutNativeCommand() async throws {
        let selection = SelectionContext(text: "Recognized text", source: .ocr)
        let result = try await CopyAction().perform(ActionContext(selection: selection))
        guard case .copy(let text) = result else { return XCTFail("OCR has no live source selection") }
        XCTAssertEqual(text, "Recognized text")
    }
    
    @MainActor
    func testPasteAction() async throws {
        let action = PasteAction()
        let context = createMockContext(with: "test string")
        
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .simulatePaste = result {
        } else {
            XCTFail("Expected .simulatePaste result")
        }
    }
    
    @MainActor
    func testSearchAction() async throws {
        let store = MemorySettingsStore()
        let action = SearchAction(settingsStore: store)
        let context = createMockContext(with: "test search")

        XCTAssertTrue(action.isEnabled(for: context))

        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://www.google.com/search?q=test%20search")
        } else {
            XCTFail("Expected .openURL result")
        }
    }

    /// perform() must honor the `url` option the Preferences sheet writes, not just the legacy key.
    @MainActor
    func testSearchActionUsesConfiguredURLOption() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.search", optionID: "url"),
                  value: "https://duckduckgo.com/?q={query}")
        let action = SearchAction(settingsStore: store)
        let result = try await action.perform(createMockContext(with: "test search"))
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=test%20search")
        } else {
            XCTFail("Expected .openURL result")
        }
    }

    /// Legacy `action.search.url` values still work; the option key takes precedence.
    @MainActor
    func testSearchActionFallsBackToLegacyKeyAndPrefersOption() async throws {
        let legacyOnly = MemorySettingsStore()
        legacyOnly.set(.searchURL, value: "https://bing.com/search?q={query}")
        let legacyResult = try await SearchAction(settingsStore: legacyOnly)
            .perform(createMockContext(with: "x"))
        if case .openURL(let url) = legacyResult {
            XCTAssertEqual(url.absoluteString, "https://bing.com/search?q=x")
        } else {
            XCTFail("Expected .openURL result from legacy key")
        }

        let both = MemorySettingsStore()
        both.set(.searchURL, value: "https://bing.com/search?q={query}")
        both.set(SettingKey.actionOption(actionID: "builtin.search", optionID: "url"),
                 value: "https://duckduckgo.com/?q={query}")
        let bothResult = try await SearchAction(settingsStore: both)
            .perform(createMockContext(with: "x"))
        if case .openURL(let url) = bothResult {
            XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=x")
        } else {
            XCTFail("Expected .openURL result with option taking precedence")
        }
    }
    
    @MainActor
    func testOpenURLAction() async throws {
        let action = OpenURLAction()
        
        let validContext = createMockContext(with: "https://apple.com")
        XCTAssertTrue(action.isEnabled(for: validContext))
        
        let validResult = try await action.perform(validContext)
        if case .openURL(let url) = validResult {
            XCTAssertEqual(url.absoluteString, "https://apple.com")
        } else {
            XCTFail("Expected .openURL result for valid URL")
        }
        
        let embeddedContext = createMockContext(with: "Check out https://github.com/apple/swift in this PR!")
        XCTAssertTrue(action.isEnabled(for: embeddedContext))
        let embeddedResult = try await action.perform(embeddedContext)
        if case .openURL(let url) = embeddedResult {
            XCTAssertEqual(url.absoluteString, "https://github.com/apple/swift")
        } else {
            XCTFail("Expected .openURL for embedded URL")
        }

        // Each distinct link opens once, in first-occurrence order.
        let multipleContext = createMockContext(with: "First https://first.com and second https://second.com then https://first.com")
        XCTAssertTrue(action.isEnabled(for: multipleContext))
        let multipleResult = try await action.perform(multipleContext)
        guard case .sequence(let effects) = multipleResult else {
            return XCTFail("Expected all distinct URLs to be opened")
        }
        XCTAssertEqual(effects.count, 2)
        XCTAssertEqual(effects.compactMap { effect -> String? in
            if case .openURL(let url) = effect { return url.absoluteString }
            return nil
        }, ["https://first.com", "https://second.com"])

        // Uppercase input is accepted.
        let bareContext = createMockContext(with: "HTTPS://APPLE.COM")
        XCTAssertTrue(action.isEnabled(for: bareContext))
        let bareResult = try await action.perform(bareContext)
        if case .openURL(let url) = bareResult {
            XCTAssertEqual(url.absoluteString, "HTTPS://APPLE.COM")
        } else {
            XCTFail("Expected .openURL for uppercase URL")
        }

        let localContext = createMockContext(with: "Server at localhost:3000/api")
        XCTAssertTrue(action.isEnabled(for: localContext))
        let localResult = try await action.perform(localContext)
        if case .openURL(let url) = localResult {
            XCTAssertEqual(url.absoluteString, "http://localhost:3000/api")
        } else {
            XCTFail("Expected .openURL for localhost")
        }

        // Angle-bracketed links are unwrapped.
        let wrappedContext = createMockContext(with: "Open <https://example.com/docs>.")
        XCTAssertTrue(action.isEnabled(for: wrappedContext))
        let wrappedResult = try await action.perform(wrappedContext)
        if case .openURL(let url) = wrappedResult {
            XCTAssertEqual(url.absoluteString, "https://example.com/docs")
        } else {
            XCTFail("Expected .openURL for wrapped web link")
        }
        
        // Test non-web schemes are rejected (mailto, ftp, magnet, custom deep links)
        let mailContext = createMockContext(with: "Send to mailto:user@example.com")
        XCTAssertFalse(action.isEnabled(for: mailContext), "mailto: scheme must not enable Open Link")
        
        let ftpContext = createMockContext(with: "ftp://files.example.com/archive.zip")
        XCTAssertFalse(action.isEnabled(for: ftpContext), "ftp: scheme must not enable Open Link")

        let magnetContext = createMockContext(with: "magnet:?xt=urn:btih:12345")
        XCTAssertFalse(action.isEnabled(for: magnetContext), "magnet: scheme must not enable Open Link")

        let deepLinkContext = createMockContext(with: "Open obsidian://open?vault=Work&file=Note")
        XCTAssertFalse(action.isEnabled(for: deepLinkContext), "custom app deep links must not enable Open Link")

        let invalidContext = createMockContext(with: "No URL here")
        XCTAssertFalse(action.isEnabled(for: invalidContext))
        
        let invalidResult = try await action.perform(invalidContext)
        if case .failure(_) = invalidResult {
        } else {
            XCTFail("Expected .failure result for invalid URL")
        }
    }
    
    @MainActor
    func testOpenURLActionInBrowserRoutesToOpenURLInApp() async throws {
        let action = OpenURLAction()
        let selection = SelectionContext(
            text: "https://brave.com",
            sourceApp: AppIdentity(bundleIdentifier: "com.brave.Browser", localizedName: "Brave Browser"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection, modifiers: [])
        let result = try await action.perform(context)
        if case .openURLInApp(let url, let appBundleIdentifier) = result {
            XCTAssertEqual(url.absoluteString, "https://brave.com")
            XCTAssertEqual(appBundleIdentifier, "com.brave.Browser")
        } else {
            XCTFail("Expected .openURLInApp result when triggered from a browser")
        }
    }
    
    @MainActor
    func testMultipleOpenLinksUseSourceBrowserAndDeduplicate() async throws {
        let selection = SelectionContext(
            text: "https://first.com https://second.com https://first.com",
            sourceApp: AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let result = try await OpenURLAction().perform(ActionContext(selection: selection))
        guard case .sequence(let effects) = result else { return XCTFail("Expected multiple links") }
        XCTAssertEqual(effects.count, 2)
        for (index, expected) in ["https://first.com", "https://second.com"].enumerated() {
            guard case .openURLInApp(let url, let bundleID) = effects[index] else { return XCTFail("Expected source browser") }
            XCTAssertEqual(url.absoluteString, expected)
            XCTAssertEqual(bundleID, "com.apple.Safari")
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
}
