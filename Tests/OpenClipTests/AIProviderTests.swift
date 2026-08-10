import XCTest
@testable import OpenClip

@MainActor
final class AIProviderTests: XCTestCase {

    // MARK: - Apple Intelligence

    func testAppleIntelligenceRejectsEmptyText() async {
        let provider = AppleIntelligenceProvider()
        do {
            _ = try await provider.process(prompt: "Summarize", text: "   \n")
            XCTFail("Expected emptyInput error")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Cloud API

    func testCloudAPIRejectsMissingKey() async {
        let provider = CloudAPIProvider(apiKey: "", model: "gpt-4o-mini")
        do {
            _ = try await provider.process(prompt: "Fix", text: "hello")
            XCTFail("Expected missingAPIKey")
        } catch let error as AIError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Ollama

    func testOllamaNormalizesEmptyBaseURLAndModel() {
        let provider = OllamaProvider(baseURL: "", model: "  ")
        XCTAssertEqual(provider.baseURL, "http://localhost:11434")
        XCTAssertEqual(provider.model, "llama3")
    }

    func testOllamaStripsTrailingSlash() {
        let provider = OllamaProvider(baseURL: "http://localhost:11434/", model: "llama3")
        XCTAssertEqual(provider.baseURL, "http://localhost:11434")
    }

    func testOllamaRejectsEmptyText() async {
        let provider = OllamaProvider(baseURL: "http://localhost:11434", model: "llama3")
        do {
            _ = try await provider.process(prompt: "Summarize", text: "\t")
            XCTFail("Expected emptyInput")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Browser redirect

    func testBrowserRedirectUsesDefaultTemplateWhenEmpty() {
        let provider = BrowserRedirectProvider(template: "")
        XCTAssertEqual(provider.template, "https://chatgpt.com/?q={text}")
    }

    // MARK: - Manager

    func testAIServiceManagerProviderTypes() {
        let manager = AIServiceManager.shared
        let previous = manager.activeProviderRaw
        defer { manager.activeProviderRaw = previous }

        manager.activeProviderType = .apple
        XCTAssertEqual(manager.currentProvider.type, .apple)

        manager.activeProviderType = .ollama
        XCTAssertEqual(manager.currentProvider.type, .ollama)

        manager.activeProviderType = .cloud
        XCTAssertEqual(manager.currentProvider.type, .cloud)

        manager.activeProviderType = .browser
        XCTAssertEqual(manager.currentProvider.type, .browser)
    }

    func testEffectiveBrowserURLTemplatePresets() {
        let manager = AIServiceManager.shared
        let previousPreset = manager.browserPreset
        let previousCustom = manager.browserURLTemplate
        defer {
            manager.browserPreset = previousPreset
            manager.browserURLTemplate = previousCustom
        }

        manager.browserPreset = "claude"
        XCTAssertTrue(manager.effectiveBrowserURLTemplate.contains("claude.ai"))

        manager.browserPreset = "custom"
        manager.browserURLTemplate = "https://example.com/ai?q={text}"
        XCTAssertEqual(manager.effectiveBrowserURLTemplate, "https://example.com/ai?q={text}")

        manager.browserURLTemplate = "   "
        XCTAssertEqual(manager.effectiveBrowserURLTemplate, "https://chatgpt.com/?q={text}")
    }

    func testAIErrorDescriptionsArePresent() {
        let errors: [AIError] = [
            .emptyInput,
            .missingAPIKey,
            .invalidURL("bad"),
            .invalidResponse,
            .httpStatus(500, "boom"),
            .httpStatus(404, nil),
            .unsupportedModel("gemini"),
            .requestTooLarge,
            .cancelled
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
