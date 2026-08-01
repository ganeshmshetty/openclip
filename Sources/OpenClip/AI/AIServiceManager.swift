import Foundation
import SwiftUI

@MainActor
public final class AIServiceManager: ObservableObject {
    public static let shared = AIServiceManager()
    
    @AppStorage("aiEnabled") public var isAIEnabled: Bool = true
    @AppStorage("aiActiveProvider") public var activeProviderRaw: String = AIProviderType.apple.rawValue
    @AppStorage("aiCloudAPIKey") public var cloudAPIKey: String = ""
    @AppStorage("aiCloudModel") public var cloudModel: String = "gpt-4o-mini"
    @AppStorage("aiOllamaURL") public var ollamaURL: String = "http://localhost:11434"
    @AppStorage("aiOllamaModel") public var ollamaModel: String = "llama3"
    @AppStorage("aiBrowserPreset") public var browserPreset: String = "chatgpt"
    @AppStorage("aiBrowserURLTemplate") public var browserURLTemplate: String = "https://chatgpt.com/?q={text}"

    private init() {}

    public var activeProviderType: AIProviderType {
        get { AIProviderType(rawValue: activeProviderRaw) ?? .apple }
        set { activeProviderRaw = newValue.rawValue }
    }

    public var effectiveBrowserURLTemplate: String {
        switch browserPreset {
        case "claude": return "https://claude.ai/new?q={text}"
        case "perplexity": return "https://www.perplexity.ai/search?q={text}"
        case "gemini": return "https://gemini.google.com/app?q={text}"
        case "deepseek": return "https://chat.deepseek.com/?q={text}"
        case "custom": return browserURLTemplate.isEmpty ? "https://chatgpt.com/?q={text}" : browserURLTemplate
        default: return "https://chatgpt.com/?q={text}"
        }
    }

    public var currentProvider: any AIProvider {
        switch activeProviderType {
        case .apple: return AppleIntelligenceProvider()
        case .ollama: return OllamaProvider(baseURL: ollamaURL, model: ollamaModel)
        case .cloud: return CloudAPIProvider(apiKey: cloudAPIKey, model: cloudModel)
        case .browser: return BrowserRedirectProvider(template: effectiveBrowserURLTemplate)
        }
    }
}
