import XCTest
@testable import OpenClip

final class CloudServiceProviderPresetTests: XCTestCase {
    func testNewPresetsUseDocumentedOpenAICompatibleEndpoints() {
        let expected: [(CloudServiceProvider, String, String)] = [
            (.mistral, "Mistral", "https://api.mistral.ai/v1"),
            (.xai, "xAI", "https://api.x.ai/v1"),
            (.cerebras, "Cerebras", "https://api.cerebras.ai/v1"),
            (.together, "Together AI", "https://api.together.ai/v1"),
            (.fireworks, "Fireworks", "https://api.fireworks.ai/inference/v1"),
            (.opencode, "OpenCode", "https://opencode.ai/inference/openai/v1"),
            (.opencodeGo, "OpenCode Go", "https://opencode.ai/inference/go/openai/v1"),
        ]
        for (provider, name, url) in expected {
            XCTAssertEqual(provider.displayName, name)
            XCTAssertEqual(provider.defaultBaseURL, url, provider.rawValue)
            XCTAssertTrue(provider.defaultModels.contains(provider.primaryModel), provider.rawValue)
            XCTAssertFalse(provider.defaultModels.isEmpty)
        }
    }

    func testPresetOrderKeepsCustomLast() {
        let ids = CloudServiceProvider.allCases.map(\.rawValue)
        XCTAssertEqual(
            Array(ids.prefix(6)),
            ["openai", "anthropic", "google", "deepseek", "groq", "openrouter"]
        )
        XCTAssertEqual(
            Array(ids.suffix(6)),
            ["mistral", "xai", "cerebras", "together", "fireworks", "custom"]
        )
    }

    func testNewPresetsRequireAnAPIKeyBeforeListingModels() async {
        for provider in [CloudServiceProvider.mistral, .xai, .cerebras, .together, .fireworks, .opencode, .opencodeGo] {
            do {
                _ = try await CloudAPIProvider.fetchAvailableModels(apiKey: "  ", provider: provider)
                XCTFail("expected a missing API key for \(provider.rawValue)")
            } catch let error as AIError {
                XCTAssertEqual(error, .missingAPIKey, provider.rawValue)
            } catch {
                XCTFail("unexpected error for \(provider.rawValue): \(error)")
            }
        }
    }

    func testModelQueryFiltersBySubstringAndKeepsTheCurrentSelection() {
        let models = ["default", "openai/gpt-oss-120b", "meta-llama/llama-3.3-70b", "qwen/qwen3"]
        XCTAssertEqual(CloudModelCatalog.matching(models, query: "  "), models)
        XCTAssertEqual(CloudModelCatalog.matching(models, query: "QWEN"), ["qwen/qwen3"])
        XCTAssertEqual(
            CloudModelCatalog.matching(models, query: "llama", keeping: "openai/gpt-oss-120b"),
            ["openai/gpt-oss-120b", "meta-llama/llama-3.3-70b"]
        )
        XCTAssertEqual(
            CloudModelCatalog.matching(models, query: "llama", keeping: "custom"),
            ["meta-llama/llama-3.3-70b"]
        )
        XCTAssertEqual(
            CloudModelCatalog.matching(models, query: "Default", label: { $0 == "default" ? "Default" : $0 }),
            ["default"]
        )
    }

    func testVideoAndVoiceModelsAreNotChatModels() {
        XCTAssertFalse(CloudModelCatalog.isChatModel("grok-imagine-video-1.5"))
        XCTAssertFalse(CloudModelCatalog.isChatModel("grok-voice-3.0"))
        XCTAssertTrue(CloudModelCatalog.isChatModel("grok-4.7"))
    }
}
