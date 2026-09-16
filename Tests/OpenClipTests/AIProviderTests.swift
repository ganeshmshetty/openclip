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

    // MARK: - Local LLM

    func testLocalLLMNormalizesEmptyBaseURLAndModel() {
        let provider = LocalLLMProvider(baseURL: "", model: "  ")
        XCTAssertEqual(provider.baseURL, "http://localhost:1234/v1")
        XCTAssertEqual(provider.model, "default")
    }

    func testLocalLLMStripsTrailingSlash() {
        let provider = LocalLLMProvider(baseURL: "http://localhost:1234/v1/", model: "default")
        XCTAssertEqual(provider.baseURL, "http://localhost:1234/v1")
    }

    func testLocalLLMRejectsEmptyText() async {
        let provider = LocalLLMProvider(baseURL: "http://localhost:1234/v1", model: "default")
        do {
            _ = try await provider.process(prompt: "Summarize", text: "\t")
            XCTFail("Expected emptyInput")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - CLI Provider

    func testCLIProviderInitialization() {
        let provider = CLIProvider(preset: .claude, customCommand: "", modelOverride: "sonnet")
        XCTAssertEqual(provider.type, .cli)
        XCTAssertEqual(provider.preset, .claude)
        XCTAssertEqual(provider.modelOverride, "sonnet")
    }

    func testCLIPresetLoginCommandsAndModels() {
        XCTAssertEqual(CLIPreset.claude.loginCommand, "claude auth login")
        XCTAssertEqual(CLIPreset.codex.loginCommand, "codex")
        XCTAssertEqual(CLIPreset.copilot.loginCommand, "gh auth login")
        XCTAssertFalse(CLIPreset.claude.authHelpText.isEmpty)
        XCTAssertTrue(CLIPreset.claude.defaultModels.contains("sonnet"))
        XCTAssertTrue(CLIPreset.codex.defaultModels.contains("o3-mini"))
    }

    func testEffectiveCLIModelResolution() {
        let manager = AIServiceManager.shared
        let previousCLIModel = manager.cliModel
        let previousCLICustomModel = manager.cliCustomModel
        defer {
            manager.cliModel = previousCLIModel
            manager.cliCustomModel = previousCLICustomModel
        }

        manager.cliModel = "default"
        XCTAssertEqual(manager.effectiveCLIModel, "")

        manager.cliModel = "sonnet"
        XCTAssertEqual(manager.effectiveCLIModel, "sonnet")

        manager.cliModel = "custom"
        manager.cliCustomModel = "claude-3-7-sonnet-20250219"
        XCTAssertEqual(manager.effectiveCLIModel, "claude-3-7-sonnet-20250219")
    }

    func testCLIProviderRejectsEmptyText() async {
        let provider = CLIProvider(preset: .claude)
        do {
            _ = try await provider.process(prompt: "Summarize", text: "  ")
            XCTFail("Expected emptyInput")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Manager

    func testAIServiceManagerProviderTypes() {
        let manager = AIServiceManager.shared
        let previous = manager.activeProviderRaw
        defer { manager.activeProviderRaw = previous }

        manager.activeProviderType = .apple
        XCTAssertEqual(manager.currentProvider.type, .apple)

        manager.activeProviderType = .local
        XCTAssertEqual(manager.currentProvider.type, .local)

        manager.activeProviderType = .cli
        XCTAssertEqual(manager.currentProvider.type, .cli)

        manager.activeProviderType = .cloud
        XCTAssertEqual(manager.currentProvider.type, .cloud)
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

        // Title tags are stripped from result text
        let withTitle = "<title>Fix Spelling</title><result>Fixed text.</result>"
        XCTAssertEqual(AIRequestSupport.extractResultText(withTitle), "Fixed text.")
        XCTAssertEqual(AIRequestSupport.extractTitleText(withTitle), "Fix Spelling")

        // Incomplete/unclosed <title> suppresses output until result starts
        XCTAssertEqual(AIRequestSupport.extractResultText("<title>In progress title..."), "")
        XCTAssertEqual(AIRequestSupport.extractTitleText("<title>In progress title..."), nil)
    }

    func testTitleSanitization() {
        XCTAssertEqual(AIRequestSupport.extractTitleText("<title>  \"Clean Title\"  </title>"), "Clean Title")
        XCTAssertEqual(AIRequestSupport.extractTitleText("<title>«French Translator»</title>"), "French Translator")
        XCTAssertEqual(AIRequestSupport.extractTitleText("<title><title>Nested</title></title>"), "Nested")
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

    // MARK: - Apple Intelligence availability

    func testAppleIntelligenceAvailabilityMessagesAreActionable() {
        let statuses: [AppleIntelligenceAvailability.Status] = [
            .available, .unsupportedOS, .deviceNotEligible, .notEnabled, .modelNotReady, .unknown
        ]
        for status in statuses {
            XCTAssertFalse(AppleIntelligenceAvailability.statusLabel(for: status).isEmpty)
            XCTAssertFalse(AppleIntelligenceAvailability.unavailableExplanation(for: status).isEmpty)
        }
        XCTAssertTrue(AppleIntelligenceAvailability.Status.available.isAvailable)
        XCTAssertFalse(AppleIntelligenceAvailability.Status.notEnabled.isAvailable)
    }

    // MARK: - Structured output contract

    func testStructuredSystemPromptDropsTagInstructions() {
        let structured = AIRequestSupport.systemPrompt(for: "Summarize", structuredResult: true)
        XCTAssertFalse(structured.contains("<result>...</result>"))
        XCTAssertTrue(structured.contains("`result` field"))
        XCTAssertTrue(structured.contains("Task:\nSummarize"))

        let tagged = AIRequestSupport.systemPrompt(for: "Summarize", structuredResult: false)
        XCTAssertTrue(tagged.contains("<result>...</result>"))
    }

    func testTaggedResponseRoundTripsThroughExtractors() {
        let tagged = AIRequestSupport.taggedResponse(result: "Fixed text.", title: "Fix Spelling")
        XCTAssertEqual(AIRequestSupport.extractResultText(tagged), "Fixed text.")
        XCTAssertEqual(AIRequestSupport.extractTitleText(tagged), "Fix Spelling")

        let resultOnly = AIRequestSupport.taggedResponse(result: "Only result")
        XCTAssertEqual(AIRequestSupport.extractResultText(resultOnly), "Only result")
        XCTAssertNil(AIRequestSupport.extractTitleText(resultOnly))

        let blankTitle = AIRequestSupport.taggedResponse(result: "Body", title: "   ")
        XCTAssertFalse(blankTitle.contains("<title>"))
        XCTAssertEqual(AIRequestSupport.extractResultText(blankTitle), "Body")
    }

    func testTaggedResponseWithEmptyResultIsNotDetectableByExtractor() {
        // Regression: for an empty body `extractResultText` falls back to the raw `<result></result>`
        // wrapper, so it cannot flag an empty guided result. AppleIntelligenceProvider must check the
        // typed `result` field directly before re-emitting tags.
        let empty = AIRequestSupport.taggedResponse(result: "")
        XCTAssertEqual(empty, "<result></result>")
        XCTAssertFalse(AIRequestSupport.extractResultText(empty).isEmpty)
    }

    func testTaggedResponseStripsLeakedTagMarkup() {
        // A text-shaped prompt can still tell the model to emit tags; guided generation may then
        // place that literal markup inside a field. It must not survive the round-trip.
        let leaked = AIRequestSupport.taggedResponse(
            result: "<result>Fixed text.</result>",
            title: "<title>Fix Spelling</title>"
        )
        XCTAssertEqual(AIRequestSupport.extractResultText(leaked), "Fixed text.")
        XCTAssertEqual(AIRequestSupport.extractTitleText(leaked), "Fix Spelling")
        XCTAssertFalse(leaked.contains("<title><title>"))
    }
}
