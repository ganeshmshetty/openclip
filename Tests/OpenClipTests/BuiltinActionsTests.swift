import XCTest
@testable import Core
@testable import OpenClip

final class BuiltinActionsTests: XCTestCase {
    
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
        
        XCTAssertTrue(action.isEnabled(for: context))
        
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
        let validContext = createMockContext(with: "https://apple.com")
        XCTAssertTrue(action.isEnabled(for: validContext))
        
        let validResult = try await action.perform(validContext)
        if case .openURL(let url) = validResult {
            XCTAssertEqual(url.absoluteString, "https://apple.com")
        } else {
            XCTFail("Expected .openURL result for valid URL")
        }
        
        // Test URL embedded in surrounding text
        let embeddedContext = createMockContext(with: "Check out https://github.com/apple/swift in this PR!")
        XCTAssertTrue(action.isEnabled(for: embeddedContext))
        let embeddedResult = try await action.perform(embeddedContext)
        if case .openURL(let url) = embeddedResult {
            XCTAssertEqual(url.absoluteString, "https://github.com/apple/swift")
        } else {
            XCTFail("Expected .openURL for embedded URL")
        }

        // Test multiple links in text opens first link
        let multipleContext = createMockContext(with: "First https://first.com and second https://second.com")
        XCTAssertTrue(action.isEnabled(for: multipleContext))
        let multipleResult = try await action.perform(multipleContext)
        if case .openURL(let url) = multipleResult {
            XCTAssertEqual(url.absoluteString, "https://first.com")
        } else {
            XCTFail("Expected first URL to be extracted")
        }

        // Test bare domain & case insensitivity
        let bareContext = createMockContext(with: "HTTPS://APPLE.COM")
        XCTAssertTrue(action.isEnabled(for: bareContext))
        let bareResult = try await action.perform(bareContext)
        if case .openURL(let url) = bareResult {
            XCTAssertEqual(url.absoluteString, "HTTPS://APPLE.COM")
        } else {
            XCTFail("Expected .openURL for uppercase URL")
        }

        // Test localhost with port
        let localContext = createMockContext(with: "Server at localhost:3000/api")
        XCTAssertTrue(action.isEnabled(for: localContext))
        let localResult = try await action.perform(localContext)
        if case .openURL(let url) = localResult {
            XCTAssertEqual(url.absoluteString, "http://localhost:3000/api")
        } else {
            XCTFail("Expected .openURL for localhost")
        }

        // Test wrapped web links & punctuation wrapping
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
}
