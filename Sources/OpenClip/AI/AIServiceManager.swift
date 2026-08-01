import Foundation
import SwiftUI

@MainActor
public final class AIServiceManager: ObservableObject {
    public static let shared = AIServiceManager()

    // `@AppStorage` does not automatically publish `objectWillChange`; forward manually
    // so Preferences (and any other observers) refresh when settings change.
    @AppStorage("aiEnabled") public var isAIEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiActiveProvider") public var activeProviderRaw: String = AIProviderType.apple.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudAPIKey") public var cloudAPIKey: String = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudService") public var cloudServiceRaw: String = "openai" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudCustomURL") public var cloudCustomURL: String = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudModel") public var cloudModel: String = "gpt-4o-mini" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiOllamaURL") public var ollamaURL: String = "http://localhost:11434" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiOllamaModel") public var ollamaModel: String = "llama3" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiBrowserPreset") public var browserPreset: String = "chatgpt" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiBrowserURLTemplate") public var browserURLTemplate: String = "https://chatgpt.com/?q={text}" {
        willSet { objectWillChange.send() }
    }

    private init() {}

    public var activeProviderType: AIProviderType {
        get { AIProviderType(rawValue: activeProviderRaw) ?? .apple }
        set { activeProviderRaw = newValue.rawValue }
    }

    public var cloudServiceProvider: CloudServiceProvider {
        get { CloudServiceProvider(rawValue: cloudServiceRaw) ?? .openai }
        set {
            cloudServiceRaw = newValue.rawValue
            if let firstModel = newValue.defaultModels.first {
                cloudModel = firstModel
            }
        }
    }

    public var effectiveBrowserURLTemplate: String {
        switch browserPreset {
        case "claude": return "https://claude.ai/new?q={text}"
        case "perplexity": return "https://www.perplexity.ai/search?q={text}"
        case "gemini": return "https://gemini.google.com/app?q={text}"
        case "deepseek": return "https://chat.deepseek.com/?q={text}"
        case "custom":
            let custom = browserURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? "https://chatgpt.com/?q={text}" : custom
        default:
            return "https://chatgpt.com/?q={text}"
        }
    }

    public var currentProvider: any AIProvider {
        switch activeProviderType {
        case .apple:
            return AppleIntelligenceProvider()
        case .ollama:
            return OllamaProvider(baseURL: ollamaURL, model: ollamaModel)
        case .cloud:
            return CloudAPIProvider(apiKey: cloudAPIKey, model: cloudModel, serviceProvider: cloudServiceProvider, customBaseURL: cloudCustomURL)
        case .browser:
            return BrowserRedirectProvider(template: effectiveBrowserURLTemplate)
        }
    }
}

public enum CloudServiceProvider: String, CaseIterable, Identifiable, Sendable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case deepseek = "deepseek"
    case groq = "groq"
    case openrouter = "openrouter"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI (ChatGPT)"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google Gemini"
        case .deepseek: return "DeepSeek"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom OpenAI-Compatible Endpoint"
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-4o-mini", "gpt-4o", "o1-mini", "o1", "gpt-4-turbo"]
        case .anthropic: return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case .google: return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case .deepseek: return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .groq: return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768", "deepseek-r1-distill-llama-70b"]
        case .openrouter: return ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "deepseek/deepseek-r1", "google/gemini-2.0-flash-001"]
        case .custom: return ["default"]
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }
}
