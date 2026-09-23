import XCTest
@testable import OpenClip
import Core

@MainActor
private final class MockAIProvider: AIProvider {
    var type: AIProviderType = .local
    var responseToReturn: String = ""
    var errorToThrow: Error? = nil

    func process(prompt: String, text: String) async throws -> String {
        if let errorToThrow {
            throw errorToThrow
        }
        return responseToReturn
    }

    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if let errorToThrow {
                continuation.finish(throwing: errorToThrow)
            } else {
                continuation.yield(responseToReturn)
                continuation.finish()
            }
        }
    }
}

@MainActor
final class AICustomActionBuilderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        AIServiceManager.shared.isAIEnabled = true
    }

    override func tearDown() {
        TestIsolation.reset()
        super.tearDown()
    }

    func testGenerateSuccessfulJavaScriptAction() async throws {
        let mock = MockAIProvider()
        mock.responseToReturn = """
        <result>
        {
          "identifier": "com.openclip.user.snake-camel",
          "name": "CamelCase Converter",
          "description": "Converts snake_case to camelCase",
          "action": {
            "title": "CamelCase",
            "icon": "symbol(textformat)",
            "type": "javascript",
            "scriptCode": "function action(text) { return text.replace(/_([a-z])/g, function(_, c) { return c.toUpperCase(); }); }",
            "output": "text",
            "result": "paste-or-copy",
            "isAsync": false
          }
        }
        </result>
        """
        AIServiceManager.shared.providerOverride = mock

        let synthesis = try await AICustomActionService.generate(userPrompt: "convert snake_case to camelCase")

        XCTAssertEqual(synthesis.title, "CamelCase")
        XCTAssertEqual(synthesis.description, "Converts snake_case to camelCase")
        XCTAssertEqual(synthesis.iconSymbol, "textformat")
        XCTAssertEqual(synthesis.kind, "javascript")
        XCTAssertEqual(synthesis.delivery, .replace)
        XCTAssertFalse(synthesis.isAsync)
        XCTAssertTrue(synthesis.scriptCode.contains("function action(text)"))
    }

    func testGenerateDeliveryInferenceCopyAndPreview() async throws {
        let mock = MockAIProvider()
        mock.responseToReturn = """
        <result>
        {
          "identifier": "com.openclip.user.timestamp",
          "name": "Current Timestamp",
          "description": "Copies current epoch timestamp",
          "action": {
            "title": "Copy Timestamp",
            "icon": "clock",
            "type": "javascript",
            "scriptCode": "function action(text) { return Date.now().toString(); }",
            "output": "text",
            "result": "copy",
            "isAsync": false
          }
        }
        </result>
        """
        AIServiceManager.shared.providerOverride = mock

        let synthesis = try await AICustomActionService.generate(userPrompt: "copy current timestamp")
        XCTAssertEqual(synthesis.delivery, .copy)
        XCTAssertEqual(synthesis.iconSymbol, "clock")
    }

    func testGenerateURLAction() async throws {
        let mock = MockAIProvider()
        mock.responseToReturn = """
        <result>
        {
          "identifier": "com.openclip.user.github-search",
          "name": "GitHub Search",
          "description": "Search code on GitHub",
          "action": {
            "title": "Search GitHub",
            "icon": "link",
            "type": "url",
            "url": "https://github.com/search?q={query}",
            "result": "preview"
          }
        }
        </result>
        """
        AIServiceManager.shared.providerOverride = mock

        let synthesis = try await AICustomActionService.generate(userPrompt: "search github")
        XCTAssertEqual(synthesis.kind, "url")
        XCTAssertEqual(synthesis.delivery, .preview)
        XCTAssertEqual(synthesis.urlTemplate, "https://github.com/search?q={query}")
    }

    func testGenerateHandlesMarkdownFencesInResult() async throws {
        let mock = MockAIProvider()
        mock.responseToReturn = """
        <result>
        ```json
        {
          "identifier": "com.openclip.user.slugify",
          "name": "Slugify",
          "description": "Converts string to URL slug",
          "action": {
            "title": "Slugify",
            "icon": "link",
            "type": "javascript",
            "scriptCode": "function action(t) { return t.toLowerCase().replace(/\\\\s+/g, '-'); }",
            "output": "text",
            "result": "paste-or-copy"
          }
        }
        ```
        </result>
        """
        AIServiceManager.shared.providerOverride = mock

        let synthesis = try await AICustomActionService.generate(userPrompt: "turn text into slug")
        XCTAssertEqual(synthesis.title, "Slugify")
        XCTAssertEqual(synthesis.kind, "javascript")
        XCTAssertEqual(synthesis.delivery, .replace)
    }

    func testGenerateThrowsWhenAIDisabled() async {
        AIServiceManager.shared.isAIEnabled = false

        do {
            _ = try await AICustomActionService.generate(userPrompt: "test")
            XCTFail("Expected error when AI is disabled")
        } catch {
            // Expected
        }
    }

    func testDeliveryModesLabelsAndIcons() {
        XCTAssertEqual(AIActionDeliveryMode.replace.label, "Paste")
        XCTAssertEqual(AIActionDeliveryMode.replace.icon, "arrow.triangle.2.circlepath")

        XCTAssertEqual(AIActionDeliveryMode.copy.label, "Copy")
        XCTAssertEqual(AIActionDeliveryMode.copy.icon, "doc.on.doc")

        XCTAssertEqual(AIActionDeliveryMode.preview.label, "Show")
        XCTAssertEqual(AIActionDeliveryMode.preview.icon, "eye")
    }
}
