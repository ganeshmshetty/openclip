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
    /// Posted after the AI preset list is written; `AIActionSync` re-registers on it.
    public static let aiActionPresetsDidChange = Notification.Name("OpenClip.AIActionPresetsDidChange")
}

@MainActor
public final class AIServiceManager: ObservableObject {
    public static let shared = AIServiceManager()

    private let settingsStore = DefaultSettingsStore.shared

    // Settings-backed properties route through SettingsStore and forward `objectWillChange` so Preferences refresh.
    public var isAIEnabled: Bool {
        get { settingsStore.get(.isAIEnabled) }
        set { objectWillChange.send(); settingsStore.set(.isAIEnabled, value: newValue) }
    }
    public var activeProviderRaw: String {
        get { settingsStore.get(.aiActiveProvider) }
        set { objectWillChange.send(); settingsStore.set(.aiActiveProvider, value: newValue) }
    }
    /// Re-entrancy guard: reverting `cloudAPIKey` after a failed SecretStore write re-enters `didSet` and can ping-pong forever (issue #42).
    private var isRevertingCloudAPIKey = false

    // API key is stored in ~/.openclip/secrets.json via SecretStore.
    @Published public var cloudAPIKey: String {
        didSet {
            guard !isRevertingCloudAPIKey else { return }
            if cloudAPIKey.isEmpty {
                SecretStore.delete(account: Self.cloudAPIKeyAccount)
            } else {
                let didStore = SecretStore.set(cloudAPIKey, account: Self.cloudAPIKeyAccount)
                if !didStore {
                    Log.settings.error("Failed to persist cloud API key to SecretStore; reverting value.")
                    isRevertingCloudAPIKey = true
                    defer { isRevertingCloudAPIKey = false }
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
    /// The custom system prompt guidelines as stored; empty means the built-in prompt. Read
    /// through `effectiveCustomSystemPrompt` when building a provider.
    public var customSystemPrompt: String {
        get { settingsStore.get(.aiCustomSystemPrompt) }
        set { objectWillChange.send(); settingsStore.set(.aiCustomSystemPrompt, value: Self.normalizedCustomSystemPrompt(newValue)) }
    }

    /// The guidelines handed to providers: nil unless the user changed the built-in text.
    public var effectiveCustomSystemPrompt: String? {
        let stored = Self.normalizedCustomSystemPrompt(customSystemPrompt)
        return stored.isEmpty ? nil : stored
    }

    /// What is persisted for an edited system prompt: blank, or the unchanged built-in text, is
    /// stored as "" so the built-in prompt (and any later improvement to it) keeps applying.
    public static func normalizedCustomSystemPrompt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == AIRequestSupport.defaultGuidelines.trimmingCharacters(in: .whitespacesAndNewlines) {
            return ""
        }
        return trimmed
    }

    public var actionPresetsJSON: String {
        get { settingsStore.get(.aiActionPresetsJSON) }
        set { objectWillChange.send(); settingsStore.set(.aiActionPresetsJSON, value: newValue) }
    }

    public static let defaultPresets: [AIActionPreset] = [
        AIActionPreset(id: "proofread", title: String(localized: "Proofread"), prompt: String(localized: "Correct spelling, grammar, and punctuation. Make the smallest necessary changes. Preserve wording, meaning, tone, language, and formatting. Return only the corrected text."), isEnabled: true),
        AIActionPreset(id: "rewrite", title: String(localized: "Rewrite"), prompt: String(localized: "Rewrite for clarity and natural flow. Preserve the meaning, factual details, intent, and original language. Do not add new claims. Return only the rewritten text."), isEnabled: true),
        AIActionPreset(id: "summarize", title: String(localized: "Summarize"), prompt: String(localized: "Summarize the main points in concise bullets, using the input’s language. Preserve important conclusions, decisions, and qualifications. Do not add information absent from the input."), isEnabled: true),
        AIActionPreset(id: "explain", title: String(localized: "Explain"), prompt: String(localized: "Explain the input in clear language for a beginner. Describe its main idea and important details. For code, explain what it does and how it works. Use the input’s language unless another language is requested."), isEnabled: true),
        AIActionPreset(id: "translate", title: String(localized: "Translate"), prompt: String(localized: "Translate the text accurately into natural English, preserving the original meaning, tone, and formatting"), isEnabled: true),
        AIActionPreset(id: "fix_code", title: String(localized: "Fix Code"), prompt: String(localized: "Correct identifiable syntax errors, bugs, and logic mistakes. Preserve the programming language, intended behavior, existing interfaces, and style. Make the smallest necessary changes and avoid unrelated refactoring. Return only the corrected code without markdown code fences or explanations. If a reliable fix requires essential missing context, briefly state what is needed instead of inventing code."), isEnabled: true),
        AIActionPreset(id: "make_shorter", title: String(localized: "Make Shorter"), prompt: String(localized: "Shorten the text by removing repetition and unnecessary wording. Preserve essential facts, requests, qualifications, tone, and language. Return only the shortened text."), isEnabled: true),
        AIActionPreset(id: "formal_tone", title: String(localized: "Formal Tone"), prompt: String(localized: "Rewrite in a professional, formal tone. Preserve meaning, intent, factual details, and language. Avoid inflated wording and unnecessary length. Return only the rewritten text."), isEnabled: true)
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
            // Post after the write commits so observers read the new list.
            NotificationCenter.default.post(name: .aiActionPresetsDidChange, object: self)
        }
    }

    public var enabledPresets: [AIActionPreset] {
        let list = presets.filter { $0.isEnabled }
        return list.isEmpty ? [Self.defaultPresets[0]] : list
    }

    /// Moves `id` into `gapIndex` (between-rows gap, as in the Actions outline). List order drives every AI surface.
    public func movePreset(id: String, toGap gapIndex: Int) {
        let reordered = Self.reordering(presets, moving: id, toGap: gapIndex)
        guard reordered.map(\.id) != presets.map(\.id) else { return }
        presets = reordered
    }

    /// Pure reorder for `movePreset`. Gap indices are pre-removal (SwiftUI `move` convention); an unknown id leaves the list intact.
    public static func reordering(_ presets: [AIActionPreset], moving id: String, toGap gapIndex: Int) -> [AIActionPreset] {
        guard let sourceIndex = presets.firstIndex(where: { $0.id == id }) else { return presets }
        var list = presets
        list.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: max(0, min(gapIndex, presets.count)))
        return list
    }

    /// Builds a user preset with a fresh `custom_` id, deletable like any other custom preset.
    public static func makeCustomPreset(title: String, prompt: String, requestsAdditionalInstruction: Bool = false) -> AIActionPreset {
        AIActionPreset(
            id: "custom_\(UUID().uuidString.prefix(8))",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: true,
            requestsAdditionalInstruction: requestsAdditionalInstruction
        )
    }

    /// Appends a custom preset; `AIActionSync` picks the change up via `aiActionPresetsDidChange`.
    @discardableResult
    public func addCustomPreset(title: String, prompt: String) -> AIActionPreset {
        let preset = Self.makeCustomPreset(title: title, prompt: prompt)
        updatePreset(preset)
        return preset
    }

    /// Existing preset with the same prompt (case and whitespace insensitive), so saves don't duplicate.
    public func preset(matchingPrompt prompt: String) -> AIActionPreset? {
        Self.preset(in: presets, matchingPrompt: prompt)
    }

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

    /// Maps an `ai.preset.<presetID>` action id back to the live preset.
    public func preset(forActionID actionID: String) -> AIActionPreset? {
        let prefix = "ai.preset."
        guard actionID.hasPrefix(prefix) else { return nil }
        let presetID = String(actionID.dropFirst(prefix.count))
        return presets.first { $0.id == presetID }
    }

    public func resetPresetsToDefault() {
        presets = Self.defaultPresets
    }

    /// Resolves the prompt for one run: a preset that asks for an additional instruction gets it substituted for the
    /// placeholder; otherwise a stray placeholder is stripped so it never reaches the provider. The saved preset is never modified.
    public func promptForPreset(_ preset: AIActionPreset, additionalInstruction: String? = nil) -> String {
        Self.prompt(for: preset, additionalInstruction: additionalInstruction)
    }

    /// Pure resolution behind `promptForPreset`, testable without the singleton.
    public static func prompt(for preset: AIActionPreset, additionalInstruction: String? = nil) -> String {
        if preset.requestsAdditionalInstruction, let additionalInstruction {
            return AIAdditionalInstruction.resolve(prompt: preset.prompt, with: additionalInstruction)
        }
        return AIAdditionalInstruction.containsPlaceholder(preset.prompt)
            ? AIAdditionalInstruction.removingPlaceholder(from: preset.prompt)
            : preset.prompt
    }

    private static let cloudAPIKeyAccount = "aiCloudAPIKey"

    private init() {
        Self.importSiblingBuildSettings(into: settingsStore)
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
    }

    /// The Dev and release builds keep separate preferences domains but share the API key file, so a build that was
    /// never configured would show a key with no provider. It adopts the other build's AI settings once.
    static func importSiblingBuildSettings(into store: SettingsStore, bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let bundleID, let sibling = siblingBundleID(of: bundleID),
              let defaults = UserDefaults(suiteName: sibling) else { return }
        importAISettings(into: store, from: DefaultSettingsStore(userDefaults: defaults))
    }

    static func siblingBundleID(of bundleID: String) -> String? {
        guard bundleID.hasPrefix("com.openclip.OpenClip") else { return nil }
        return bundleID.hasSuffix(".dev") ? String(bundleID.dropLast(4)) : bundleID + ".dev"
    }

    /// Copies the AI settings from `source` when `store` has never had a provider chosen and `source` has.
    @discardableResult
    static func importAISettings(into store: SettingsStore, from source: SettingsStore) -> Bool {
        let name = SettingKey.aiActiveProvider.name
        guard store.rawObject(forKey: name) == nil, source.rawObject(forKey: name) != nil else { return false }
        let snapshot = SettingsSnapshotter.capture(store: source, keys: SettingsCatalog.aiKeys, appVersion: "")
        let result = SettingsSnapshotter.apply(snapshot, to: store, keys: SettingsCatalog.aiKeys)
        Log.settings.notice("Adopted \(result.applied) AI settings from the other OpenClip build")
        return result.applied > 0
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
        provider(forPresetID: nil)
    }

    /// The provider for one action: its own provider and model when the preset sets them, otherwise
    /// the global choice. Connection details (keys, URLs, CLI tool) always come from AI settings.
    public func provider(forPresetID presetID: String?) -> any AIProvider {
        if let providerOverride {
            return providerOverride
        }
        let preset = presetID.flatMap { id in presets.first { $0.id == id } }
        let type = Self.resolvedProviderType(override: preset?.provider, fallback: activeProviderType)
        let model = preset?.model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let guidelines = effectiveCustomSystemPrompt
        switch type {
        case .apple:
            return AppleIntelligenceProvider(customGuidelines: guidelines)
        case .local:
            return LocalLLMProvider(baseURL: localURL, model: model ?? effectiveLocalModel, disableThinking: localPreset.disablesThinking, customGuidelines: guidelines)
        case .cli:
            return CLIProvider(preset: cliPreset, customCommand: cliCustomCommand, modelOverride: model ?? effectiveCLIModel, customGuidelines: guidelines)
        case .cloud:
            return CloudAPIProvider(apiKey: cloudAPIKey, model: model ?? effectiveCloudModel, serviceProvider: cloudServiceProvider, customBaseURL: cloudCustomURL, customGuidelines: guidelines)
        }
    }

    /// An unknown override, or Apple Intelligence where it is unsupported, falls back to the global provider.
    static func resolvedProviderType(override: String?, fallback: AIProviderType) -> AIProviderType {
        guard let override, let type = AIProviderType(rawValue: override),
              AIProviderType.supportedCases.contains(type) else { return fallback }
        return type
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
        case .openai: return "gpt-5-mini"
        case .anthropic: return "claude-sonnet-5-5"
        case .google: return "gemini-flash-latest"
        case .deepseek: return "deepseek-chat"
        case .groq: return "llama-3.3-70b-versatile"
        case .openrouter: return "openrouter/auto"
        case .custom: return "default"
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-5-mini", "gpt-5", "gpt-5-nano", "gpt-4.1"]
        case .anthropic: return ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]
        case .google: return ["gemini-flash-latest", "gemini-flash-lite-latest", "gemini-pro-latest"]
        case .deepseek: return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .groq: return ["llama-3.3-70b-versatile", "openai/gpt-oss-120b", "openai/gpt-oss-20b"]
        case .openrouter: return ["openrouter/auto"]
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
    /// `AIProviderType` raw value to run this action on; nil uses the provider chosen in AI settings.
    public var provider: String?
    /// Model for the chosen provider (or the global one when `provider` is nil); blank uses that provider's model from AI settings.
    public var model: String?
    /// Running the preset first asks for a one-time instruction that replaces `{{additional_instruction}}` in `prompt`.
    public var requestsAdditionalInstruction: Bool

    public init(
        id: String, title: String, prompt: String, isEnabled: Bool = true,
        provider: String? = nil, model: String? = nil, requestsAdditionalInstruction: Bool = false
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.provider = provider
        self.model = model
        self.requestsAdditionalInstruction = requestsAdditionalInstruction
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, isEnabled, provider, model, requestsAdditionalInstruction
    }

    /// Presets saved before `requestsAdditionalInstruction` existed decode with it off instead of failing the whole list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        requestsAdditionalInstruction = try container.decodeIfPresent(Bool.self, forKey: .requestsAdditionalInstruction) ?? false
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
