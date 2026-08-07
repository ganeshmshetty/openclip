// AIServiceManager.swift
// OpenClip
//
// Manages AI service provider selection, API credentials, and invocation of AI text processing actions.
import Foundation
import SwiftUI
import Core

extension Notification.Name {
    /// Posted by `AIServiceManager` after the AI preset list has been written, so observers
    /// (e.g. `AIActionSync`) can re-register AI actions against the freshly committed list.
    public static let aiActionPresetsDidChange = Notification.Name("OpenClip.AIActionPresetsDidChange")
}

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
    // API key is stored in the Keychain (not UserDefaults) via KeychainStore.
    @Published public var cloudAPIKey: String {
        didSet {
            if cloudAPIKey.isEmpty {
                KeychainStore.delete(account: Self.cloudAPIKeyAccount)
            } else {
                let didStore = KeychainStore.set(cloudAPIKey, account: Self.cloudAPIKeyAccount)
                if !didStore {
                    // Keychain writes can fail (e.g. keychain locked, ACL mismatch). Don't leave the
                    // observable value claiming a key that won't survive restart — revert so the
                    // caller/UI can see the change was not persisted.
                    Log.settings.error("Failed to persist cloud API key to Keychain; reverting value.")
                    cloudAPIKey = oldValue
                }
            }
        }
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
    @AppStorage("aiActionPresetsJSON") public var actionPresetsJSON: String = "" {
        willSet { objectWillChange.send() }
    }

    public static let defaultPresets: [AIActionPreset] = [
        AIActionPreset(id: "proofread", title: "Proofread", prompt: "Fix spelling and grammar errors", isEnabled: true),
        AIActionPreset(id: "rewrite", title: "Rewrite", prompt: "Rephrase and polish text", isEnabled: true),
        AIActionPreset(id: "summarize", title: "Summarize", prompt: "Summarize text into key points", isEnabled: true),
        AIActionPreset(id: "explain", title: "Explain", prompt: "Explain this text or concept simply", isEnabled: true),
        AIActionPreset(id: "translate", title: "Translate", prompt: "Translate text into English", isEnabled: true),
        AIActionPreset(id: "fix_code", title: "Fix Code", prompt: "Analyze and fix bugs in selected code", isEnabled: false),
        AIActionPreset(id: "make_shorter", title: "Make Shorter", prompt: "Make text concise and brief", isEnabled: false),
        AIActionPreset(id: "formal_tone", title: "Formal Tone", prompt: "Rewrite text in a professional and formal tone", isEnabled: false)
    ]

    public var presets: [AIActionPreset] {
        get {
guard !actionPresetsJSON.isEmpty,
              let data = actionPresetsJSON.data(using: .utf8) else {
            return Self.defaultPresets
        }
        if let decoded = try? JSONDecoder().decode([AIActionPreset].self, from: data) {
            return decoded
        }
        Log.ai.error("Failed to decode saved AI action presets; using defaults")
        return Self.defaultPresets
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                actionPresetsJSON = str
            } else {
                Log.ai.error("Failed to encode AI action presets for persistence")
            }
            // Posted after the value above has committed, so observers always read the fresh list
            // (objectWillChange fires before @AppStorage lands). AIActionSync keeps the registered
            // AI actions in step with this list.
            NotificationCenter.default.post(name: .aiActionPresetsDidChange, object: self)
        }
    }

    public var enabledPresets: [AIActionPreset] {
        let list = presets.filter { $0.isEnabled }
        return list.isEmpty ? [Self.defaultPresets[0]] : list
    }

    public func updatePreset(_ updated: AIActionPreset) {
        var current = presets
        if let idx = current.firstIndex(where: { $0.id == updated.id }) {
            current[idx] = updated
        } else {
            current.append(updated)
        }
        presets = current
    }

    /// Maps a registered AI action id (`ai.preset.<presetID>`, see `AIAction`) back to its live
    /// preset, so palette/preferences routing can resolve the preset without touching `AIAction`'s
    /// internals.
    public func preset(forActionID actionID: String) -> AIActionPreset? {
        let prefix = "ai.preset."
        guard actionID.hasPrefix(prefix) else { return nil }
        let presetID = String(actionID.dropFirst(prefix.count))
        return presets.first { $0.id == presetID }
    }

    public func resetPresetsToDefault() {
        presets = Self.defaultPresets
    }

    private static let cloudAPIKeyAccount = "aiCloudAPIKey"

    private init() {
        // Load the API key from the Keychain, migrating any legacy UserDefaults value on first launch.
        if let stored = KeychainStore.get(account: Self.cloudAPIKeyAccount) {
            self.cloudAPIKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: "aiCloudAPIKey"), !legacy.isEmpty {
            // Persist to the Keychain before dropping the legacy value. If storage fails, keep the
            // legacy value in UserDefaults so the credential is not lost and the migration retries
            // on the next launch. (Property observers don't fire during init, so set explicitly.)
            if KeychainStore.set(legacy, account: Self.cloudAPIKeyAccount) {
                UserDefaults.standard.removeObject(forKey: "aiCloudAPIKey")
            }
            self.cloudAPIKey = legacy
        } else {
            self.cloudAPIKey = ""
        }
    }

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

public struct AIActionPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var prompt: String
    public var isEnabled: Bool

    public init(id: String, title: String, prompt: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
    }
}
