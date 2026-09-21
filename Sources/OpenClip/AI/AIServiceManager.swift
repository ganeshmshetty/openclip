// AIServiceManager.swift
// OpenClip
//
// Manages AI service provider selection, API credentials, and invocation of AI text processing actions.
import Foundation
import os
import SwiftUI
import Core
import os

extension Notification.Name {
    /// Posted by `AIServiceManager` after the AI preset list has been written, so observers
    /// (e.g. `AIActionSync`) can re-register AI actions against the freshly committed list.
    public static let aiActionPresetsDidChange = Notification.Name("OpenClip.AIActionPresetsDidChange")
}

@MainActor
public final class AIServiceManager: ObservableObject {
    public static let shared = AIServiceManager()

    private let settingsStore = DefaultSettingsStore.shared

    // Settings-backed properties route through SettingsStore (the single settings door) and
    // manually forward `objectWillChange` so Preferences (and any other observers) refresh when
    // a value changes. Key names and defaults are unchanged from the former @AppStorage surface.
    public var isAIEnabled: Bool {
        get { settingsStore.get(.isAIEnabled) }
        set { objectWillChange.send(); settingsStore.set(.isAIEnabled, value: newValue) }
    }
    public var activeProviderRaw: String {
        get { settingsStore.get(.aiActiveProvider) }
        set { objectWillChange.send(); settingsStore.set(.aiActiveProvider, value: newValue) }
    }
    // API key is stored in ~/.openclip/secrets.json via SecretStore.
    @Published public var cloudAPIKey: String {
        didSet {
            if cloudAPIKey.isEmpty {
                SecretStore.delete(account: Self.cloudAPIKeyAccount)
            } else {
                let didStore = SecretStore.set(cloudAPIKey, account: Self.cloudAPIKeyAccount)
                if !didStore {
                    Log.settings.error("Failed to persist cloud API key to SecretStore; reverting value.")
                    cloudAPIKey = oldValue
                }
            }
        }
    }
    public var cloudServiceRaw: String {
        get { settingsStore.get(.aiCloudService) }
        set { objectWillChange.send(); settingsStore.set(.aiCloudService, value: newValue) }
    }
    public var cloudCustomURL: String {
        get { settingsStore.get(.aiCloudCustomURL) }
        set { objectWillChange.send(); settingsStore.set(.aiCloudCustomURL, value: newValue) }
    }
    public var cloudModel: String {
        get { settingsStore.get(.aiCloudModel) }
        set { objectWillChange.send(); settingsStore.set(.aiCloudModel, value: newValue) }
    }
    public var localPresetRaw: String {
        get { settingsStore.get(.aiLocalPreset) }
        set { objectWillChange.send(); settingsStore.set(.aiLocalPreset, value: newValue) }
    }
    public var localURL: String {
        get { settingsStore.get(.aiLocalURL) }
        set { objectWillChange.send(); settingsStore.set(.aiLocalURL, value: newValue) }
    }
    public var localModel: String {
        get { settingsStore.get(.aiLocalModel) }
        set { objectWillChange.send(); settingsStore.set(.aiLocalModel, value: newValue) }
    }
    public var cliPresetRaw: String {
        get { settingsStore.get(.aiCLIPreset) }
        set { objectWillChange.send(); settingsStore.set(.aiCLIPreset, value: newValue) }
    }
    public var cliCustomCommand: String {
        get { settingsStore.get(.aiCLICustomCommand) }
        set { objectWillChange.send(); settingsStore.set(.aiCLICustomCommand, value: newValue) }
    }
    public var cliModel: String {
        get { settingsStore.get(.aiCLIModel) }
        set { objectWillChange.send(); settingsStore.set(.aiCLIModel, value: newValue) }
    }
    public var cliCustomModel: String {
        get { settingsStore.get(.aiCLICustomModel) }
        set { objectWillChange.send(); settingsStore.set(.aiCLICustomModel, value: newValue) }
    }
    public var cliCustomAuthCommand: String {
        get { settingsStore.get(.aiCLICustomAuthCommand) }
        set { objectWillChange.send(); settingsStore.set(.aiCLICustomAuthCommand, value: newValue) }
    }
    public var localCustomModel: String {
        get { settingsStore.get(.aiLocalCustomModel) }
        set { objectWillChange.send(); settingsStore.set(.aiLocalCustomModel, value: newValue) }
    }
    public var cloudCustomModel: String {
        get { settingsStore.get(.aiCloudCustomModel) }
        set { objectWillChange.send(); settingsStore.set(.aiCloudCustomModel, value: newValue) }
    }

    public var effectiveCLIModel: String {
        if cliModel == "custom" {
            return cliCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (cliModel == "default") ? "" : cliModel
    }

    public var effectiveLocalModel: String {
        if localModel == "custom" {
            return localCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return localModel
    }

    public var effectiveCloudModel: String {
        if cloudModel == "custom" {
            let trimmed = cloudCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? cloudServiceProvider.primaryModel : trimmed
        }
        return (cloudModel == "default") ? cloudServiceProvider.primaryModel : cloudModel
    }

    public var localPreset: LocalLLMPreset {
        get { LocalLLMPreset(rawValue: localPresetRaw) ?? .lmstudio }
        set {
            localPresetRaw = newValue.rawValue
            localURL = newValue.defaultBaseURL
            if let first = newValue.defaultModels.first {
                localModel = first
            }
        }
    }

    public var cliPreset: CLIPreset {
        get { CLIPreset(rawValue: cliPresetRaw) ?? .claude }
        set {
            cliPresetRaw = newValue.rawValue
            if let first = newValue.defaultModels.first {
                cliModel = first
            }
        }
    }

    /// Backwards-compatibility properties for existing settings
    public var ollamaURL: String {
        get { localURL }
        set { localURL = newValue }
    }
    public var ollamaModel: String {
        get { localModel }
        set { localModel = newValue }
    }
    public var actionPresetsJSON: String {
        get { settingsStore.get(.aiActionPresetsJSON) }
        set { objectWillChange.send(); settingsStore.set(.aiActionPresetsJSON, value: newValue) }
    }

    public static let defaultPresets: [AIActionPreset] = [
        AIActionPreset(id: "proofread", title: String(localized: "Proofread"), prompt: String(localized: "Fix all spelling, punctuation, and grammar errors with the smallest possible changes. Preserve the original wording, tone, and formatting — do not rewrite or rephrase sentences"), isEnabled: true),
        AIActionPreset(id: "rewrite", title: String(localized: "Rewrite"), prompt: String(localized: "Rewrite to improve clarity, flow, and word choice while keeping the original meaning, tone, language, and formatting"), isEnabled: true),
        AIActionPreset(id: "summarize", title: String(localized: "Summarize"), prompt: String(localized: "Provide a concise bulleted summary of the key points, in the same language as the text. Include only essential information — no introduction or closing remarks"), isEnabled: true),
        AIActionPreset(id: "explain", title: String(localized: "Explain"), prompt: String(localized: "Explain what the text means in clear, simple language, in the same language as the text. Cover the core idea and any important details a beginner would need"), isEnabled: true),
        AIActionPreset(id: "translate", title: String(localized: "Translate"), prompt: String(localized: "Translate the text accurately into natural English, preserving the original meaning, tone, and formatting"), isEnabled: true),
        AIActionPreset(id: "fix_code", title: String(localized: "Fix Code"), prompt: String(localized: "Fix bugs, syntax errors, and logic issues in this code. Keep the same programming language, style, and structure, and change as little as possible. Return only the raw working code — no markdown code fences, no explanations"), isEnabled: true),
        AIActionPreset(id: "make_shorter", title: String(localized: "Make Shorter"), prompt: String(localized: "Condense this text to be significantly shorter while keeping all essential information, the original language, and the tone. Preserve the overall formatting such as paragraphs and lists"), isEnabled: true),
        AIActionPreset(id: "formal_tone", title: String(localized: "Formal Tone"), prompt: String(localized: "Rewrite this text in a polished, professional, and formal tone. Keep the original meaning, language, and formatting; replace slang, contractions, and casual phrasing with formal equivalents"), isEnabled: true)
    ]

    private static let presetDecodeFailureLogged = OSAllocatedUnfairLock(initialState: false)

    public var presets: [AIActionPreset] {
        get {
            guard !actionPresetsJSON.isEmpty,
                  let data = actionPresetsJSON.data(using: .utf8) else {
                return Self.defaultPresets
            }
            if let decoded = try? JSONDecoder().decode([AIActionPreset].self, from: data) {
                return decoded
            }
            Self.presetDecodeFailureLogged.withLock { alreadyLogged in
                guard !alreadyLogged else { return }
                alreadyLogged = true
                Log.ai.error("Failed to decode saved AI action presets; using defaults")
            }
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

    /// Reorders the preset list, moving `id` into `gapIndex` — the gap the insertion bar was
    /// drawn in, counted between rows (0 = above the first, `count` = below the last), matching
    /// the drop semantics of the Actions outline. The list order *is* the order everywhere — the
    /// AI sub-bar, the search palette, and the Preferences list all read it — so persisting the
    /// new array is the whole feature.
    public func movePreset(id: String, toGap gapIndex: Int) {
        let reordered = Self.reordering(presets, moving: id, toGap: gapIndex)
        guard reordered.map(\.id) != presets.map(\.id) else { return }
        presets = reordered
    }

    /// Pure reorder used by `movePreset`, split out so the ordering rules are testable without the
    /// `@AppStorage`-backed singleton. Gap indices are pre-removal (SwiftUI's `move(fromOffsets:
    /// toOffset:)` convention), so dropping into the gap directly below a row is a no-op rather
    /// than an off-by-one. An unknown id or an out-of-range gap leaves the list intact — the gap
    /// is clamped, never trapped on.
    public static func reordering(_ presets: [AIActionPreset], moving id: String, toGap gapIndex: Int) -> [AIActionPreset] {
        guard let sourceIndex = presets.firstIndex(where: { $0.id == id }) else { return presets }
        var list = presets
        list.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: max(0, min(gapIndex, presets.count)))
        return list
    }

    /// Builds a user-authored preset with a fresh `custom_` id — the same shape the "Add Custom AI
    /// Action" sheet writes, so it is deletable in AI → Actions like any other custom preset.
    /// Pure, so the id/title/prompt rules are testable without the `@AppStorage` singleton.
    public static func makeCustomPreset(title: String, prompt: String) -> AIActionPreset {
        AIActionPreset(
            id: "custom_\(UUID().uuidString.prefix(8))",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: true
        )
    }

    /// Appends a new custom preset and returns it. The preset list is the single source of truth
    /// for every AI surface (palette, AI sub-bar, Preferences), so persisting it is the whole
    /// registration — `AIActionSync` picks the change up through `aiActionPresetsDidChange`.
    @discardableResult
    public func addCustomPreset(title: String, prompt: String) -> AIActionPreset {
        let preset = Self.makeCustomPreset(title: title, prompt: prompt)
        updatePreset(preset)
        return preset
    }

    /// The preset whose prompt is `prompt` (case- and whitespace-insensitive), if one exists — so
    /// saving a prompt the user already saved reuses that tool instead of minting a duplicate.
    public func preset(matchingPrompt prompt: String) -> AIActionPreset? {
        Self.preset(in: presets, matchingPrompt: prompt)
    }

    /// Pure lookup behind `preset(matchingPrompt:)`.
    public static func preset(in presets: [AIActionPreset], matchingPrompt prompt: String) -> AIActionPreset? {
        let wanted = normalizedPrompt(prompt)
        guard !wanted.isEmpty else { return nil }
        return presets.first { normalizedPrompt($0.prompt) == wanted }
    }

    private static func normalizedPrompt(_ prompt: String) -> String {
        prompt
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .lowercased()
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

    /// Resolves the effective prompt for an AI preset.
    public func promptForPreset(_ preset: AIActionPreset) -> String {
        preset.prompt
    }

    private static let cloudAPIKeyAccount = "aiCloudAPIKey"

    private init() {
        // Load the API key from the SecretStore (~/.openclip/secrets.json)
        if let stored = SecretStore.get(account: Self.cloudAPIKeyAccount) {
            self.cloudAPIKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: "aiCloudAPIKey"), !legacy.isEmpty {
            if SecretStore.set(legacy, account: Self.cloudAPIKeyAccount) {
                UserDefaults.standard.removeObject(forKey: "aiCloudAPIKey")
            }
            self.cloudAPIKey = legacy
        } else {
            self.cloudAPIKey = ""
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: "aiLocalURL") == nil,
           let legacyURL = defaults.string(forKey: "aiOllamaURL"), !legacyURL.isEmpty {
            localURL = legacyURL
            localPresetRaw = LocalLLMPreset.ollama.rawValue
        }
        if defaults.object(forKey: "aiLocalModel") == nil,
           let legacyModel = defaults.string(forKey: "aiOllamaModel"), !legacyModel.isEmpty {
            localModel = legacyModel
        }

        if !AppleIntelligenceAvailability.isSupported && activeProviderRaw == "apple" {
            activeProviderRaw = AIProviderType.local.rawValue
        }
    }

    public var activeProviderType: AIProviderType {
        get {
            switch activeProviderRaw {
            case "apple":
                return AppleIntelligenceAvailability.isSupported ? .apple : .local
            case "local", "ollama":
                return .local
            case "cli":
                return .cli
            case "cloud":
                return .cloud
            default:
                return AppleIntelligenceAvailability.isSupported ? .apple : .local
            }
        }
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

    /// Overrides the AI provider instance (for testing/mocking).
    public var providerOverride: (any AIProvider)? = nil

    public var currentProvider: any AIProvider {
        if let providerOverride {
            return providerOverride
        }
        switch activeProviderType {
        case .apple:
            return AppleIntelligenceProvider()
        case .local:
            return LocalLLMProvider(baseURL: localURL, model: effectiveLocalModel)
        case .cli:
            return CLIProvider(preset: cliPreset, customCommand: cliCustomCommand, modelOverride: effectiveCLIModel)
        case .cloud:
            return CloudAPIProvider(apiKey: cloudAPIKey, model: effectiveCloudModel, serviceProvider: cloudServiceProvider, customBaseURL: cloudCustomURL)
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
        case .openai: return String(localized: "OpenAI (ChatGPT)")
        case .anthropic: return String(localized: "Anthropic (Claude)")
        case .google: return String(localized: "Google Gemini")
        case .deepseek: return String(localized: "DeepSeek")
        case .groq: return String(localized: "Groq")
        case .openrouter: return String(localized: "OpenRouter")
        case .custom: return String(localized: "Custom OpenAI-Compatible Endpoint")
        }
    }

    public var primaryModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-7-sonnet-latest"
        case .google: return "gemini-2.0-flash"
        case .deepseek: return "deepseek-chat"
        case .groq: return "llama-3.3-70b-versatile"
        case .openrouter: return "openai/gpt-4o-mini"
        case .custom: return "default"
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-4o-mini", "gpt-4o", "o3-mini", "o1", "gpt-4-turbo"]
        case .anthropic: return ["claude-3-7-sonnet-latest", "claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case .google: return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case .deepseek: return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .groq: return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768", "deepseek-r1-distill-llama-70b"]
        case .openrouter: return ["openai/gpt-4o-mini", "anthropic/claude-3.7-sonnet", "deepseek/deepseek-r1", "google/gemini-2.0-flash-001"]
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
