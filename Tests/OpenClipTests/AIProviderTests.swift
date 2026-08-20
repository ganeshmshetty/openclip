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
            .providerUnavailable("Apple Intelligence is not available on this device"),
            .requestTooLarge,
            .cancelled
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    // MARK: - Extract Result & Reasoning Tags

    func testExtractResultText() {
        // Standard XML tags
        XCTAssertEqual(AIRequestSupport.extractResultText("<result>Clean text</result>"), "Clean text")
        XCTAssertEqual(AIRequestSupport.extractResultText("<output>Clean output</output>"), "Clean output")
        
        // DeepSeek/reasoning <think> tag stripping
        let thinkingOutput = "<think>Analyzing grammar and spelling...</think><result>Corrected sentence.</result>"
        XCTAssertEqual(AIRequestSupport.extractResultText(thinkingOutput), "Corrected sentence.")

        // Unclosed <think> during streaming should return empty to suppress raw thinking tokens
        let partialThink = "<think>Analyzing user prompt..."
        XCTAssertEqual(AIRequestSupport.extractResultText(partialThink), "")

        // Unclosed <result> tag during streaming should return in-progress content
        let partialResult = "<result>In progress streaming text"
        XCTAssertEqual(AIRequestSupport.extractResultText(partialResult), "In progress streaming text")

        // Empty closed tags should fall back to original text rather than returning closing tag
        XCTAssertEqual(AIRequestSupport.extractResultText("<result></result>"), "<result></result>")
        XCTAssertEqual(AIRequestSupport.extractResultText("<output>   </output>"), "<output>   </output>")

        // Plain text without tags
        XCTAssertEqual(AIRequestSupport.extractResultText("Simple raw response"), "Simple raw response")
    }

    func testCloudAPIEffectiveBaseURL() {
        let defaultOpenAI = CloudAPIProvider(apiKey: "key", model: "gpt-4o", serviceProvider: .openai)
        XCTAssertEqual(defaultOpenAI.effectiveBaseURL, "https://api.openai.com/v1")

        let customAnthropic = CloudAPIProvider(apiKey: "key", model: "claude-3-5-sonnet", serviceProvider: .anthropic, customBaseURL: "https://my-proxy.internal/v1")
        XCTAssertEqual(customAnthropic.effectiveBaseURL, "https://my-proxy.internal/v1")
    }

    func testSystemPromptAndUserContentFormatting() {
        let customPrompt = "Translate into pirate English"
        let systemPrompt = AIRequestSupport.systemPrompt(for: customPrompt)
        XCTAssertTrue(systemPrompt.contains("Task:\nTranslate into pirate English"))
        XCTAssertTrue(systemPrompt.contains("Output ONLY the transformed text"))
        XCTAssertTrue(systemPrompt.contains("<result>...</result>"))

        let emptyTaskPrompt = AIRequestSupport.systemPrompt(for: "  ")
        XCTAssertFalse(emptyTaskPrompt.contains("Task:"))

        let userContent = AIRequestSupport.userContent(for: "Hello World")
        XCTAssertEqual(userContent, "<text>\nHello World\n</text>")
    }
}
