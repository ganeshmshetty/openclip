// AIPresetModelSection.swift
// OpenClip
//
// Lets one AI action run on its own provider and model instead of the global choice.
import SwiftUI
import Core

struct AIPresetModelSection: View {
    @Binding var provider: String?
    @Binding var model: String?
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var fetchedModels: [String] = []
    @State private var isCustom = false

    private static let customTag = "__custom__"

    private var effectiveType: AIProviderType {
        AIServiceManager.resolvedProviderType(override: provider, fallback: aiManager.activeProviderType)
    }

    var body: some View {
        SettingsCard("Model") {
            VStack(spacing: 0) {
                SettingsRow(title: "Provider", info: "Run this action on a different provider than the one chosen in AI settings. Keys and endpoints still come from AI settings.") {
                    Picker("Provider", selection: Binding(
                        get: { provider ?? "" },
                        set: { provider = $0.isEmpty ? nil : $0; model = nil; isCustom = false }
                    )) {
                        Text("Default").tag("")
                        ForEach(AIProviderType.supportedCases) { type in
                            Text(type.shortTitle).tag(type.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if effectiveType != .apple {
                    SettingsDivider(insetLeading: SettingsDesignTokens.sectionCardPaddingH)

                    SettingsRow(title: "Model") {
                        Picker("Model", selection: modelSelection) {
                            Text("Default").tag("")
                            ForEach(choices, id: \.self) { Text($0).tag($0) }
                            Text("Custom…").tag(Self.customTag)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    if isCustom {
                        TextField("Model identifier", text: Binding(
                            get: { model ?? "" },
                            set: { model = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                        .padding(.bottom, SettingsDesignTokens.sectionCardPaddingV)
                    }
                }
            }
        }
        .task(id: effectiveType) { await loadChoices() }
        .onAppear { isCustom = model.map { !$0.isEmpty && !choices.contains($0) } ?? false }
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { isCustom ? Self.customTag : (model ?? "") },
            set: { picked in
                if picked == Self.customTag {
                    isCustom = true
                } else {
                    isCustom = false
                    model = picked.isEmpty ? nil : picked
                }
            }
        )
    }

    private var choices: [String] {
        var list: [String]
        switch effectiveType {
        case .local:
            list = fetchedModels.isEmpty ? aiManager.localPreset.defaultModels : fetchedModels
        case .cli:
            list = fetchedModels.isEmpty ? aiManager.cliPreset.defaultModels : fetchedModels
        case .cloud:
            list = CloudModelCatalog.choices(
                live: fetchedModels,
                cached: CloudModelCatalog.cached(for: aiManager.cloudServiceProvider),
                provider: aiManager.cloudServiceProvider,
                current: nil
            )
        case .apple:
            list = []
        }
        list.removeAll { $0 == "default" || $0 == "custom" }
        if let model, !model.isEmpty, !isCustom, !list.contains(model) { list.insert(model, at: 0) }
        return list
    }

    private func loadChoices() async {
        fetchedModels = []
        switch effectiveType {
        case .local:
            fetchedModels = (try? await LocalLLMProvider.fetchAvailableModels(baseURL: aiManager.localURL)) ?? []
        case .cli:
            fetchedModels = (try? await CLIProvider.fetchAvailableModels(for: aiManager.cliPreset)) ?? []
        case .cloud:
            let key = aiManager.cloudAPIKey
            guard !key.isEmpty || aiManager.cloudServiceProvider == .openrouter else { return }
            let provider = aiManager.cloudServiceProvider
            if let models = try? await CloudAPIProvider.fetchAvailableModels(apiKey: key, provider: provider, customBaseURL: aiManager.cloudCustomURL) {
                fetchedModels = models
                CloudModelCatalog.save(models, for: provider)
            }
        case .apple:
            break
        }
    }
}

private extension AIProviderType {
    var shortTitle: String {
        switch self {
        case .apple: return String(localized: "Apple")
        case .local: return String(localized: "Local")
        case .cli: return String(localized: "CLI")
        case .cloud: return String(localized: "Cloud")
        }
    }
}
