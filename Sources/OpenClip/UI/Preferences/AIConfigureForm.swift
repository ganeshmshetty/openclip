// AIConfigureForm.swift
// OpenClip
//
// Reusable AI engine + provider configuration form, shared by the AI preferences
// tab and the first-launch onboarding flow so both surfaces expose the same settings.
import SwiftUI

@MainActor
public struct AIConfigureForm: View {
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var fetchError: String? = nil

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $aiManager.isAIEnabled) {
                    Text("Enable AI Actions")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active AI Engine")
                        .font(.headline)
                    Text("Select which provider powers AI features when invoked.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                Picker("", selection: $aiManager.activeProviderRaw) {
                    Text("Apple").tag(AIProviderType.apple.rawValue)
                    Text("Ollama").tag(AIProviderType.ollama.rawValue)
                    Text("Cloud API").tag(AIProviderType.cloud.rawValue)
                    Text("Browser").tag(AIProviderType.browser.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(!aiManager.isAIEnabled)

            Section(header: Text("Provider Settings")) {
                if aiManager.activeProviderType == .apple {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 14, weight: .medium))
                        Text("Apple Intelligence (On-Device)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .cloud {
                    Picker("Service Provider", selection: $aiManager.cloudServiceProvider) {
                        ForEach(CloudServiceProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if aiManager.cloudServiceProvider == .custom {
                        TextField("Base Endpoint URL", text: $aiManager.cloudCustomURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    SecureField("API Key", text: $aiManager.cloudAPIKey)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        let defaultModels = aiManager.cloudServiceProvider.defaultModels
                        let combinedModels = Array(Set(defaultModels + fetchedModels + [aiManager.cloudModel])).sorted()

                        Picker("Model", selection: $aiManager.cloudModel) {
                            ForEach(combinedModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }

                        Button(action: fetchModels) {
                            if isFetchingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch available models live from API")
                        .disabled(aiManager.cloudAPIKey.isEmpty || isFetchingModels)
                    }

                    if let fetchError {
                        Text("Query failed: \(fetchError)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else if aiManager.activeProviderType == .ollama {
                    TextField("Server Endpoint", text: $aiManager.ollamaURL, prompt: Text("http://localhost:11434"))
                    TextField("Model Name", text: $aiManager.ollamaModel, prompt: Text("llama3"))
                } else if aiManager.activeProviderType == .browser {
                    Picker("Default Chatbot", selection: $aiManager.browserPreset) {
                        Text("ChatGPT (OpenAI)").tag("chatgpt")
                        Text("Claude (Anthropic)").tag("claude")
                        Text("Perplexity AI").tag("perplexity")
                        Text("Google Gemini").tag("gemini")
                        Text("DeepSeek").tag("deepseek")
                        Text("Custom URL...").tag("custom")
                    }

                    if aiManager.browserPreset == "custom" {
                        TextField("Custom Web URL", text: $aiManager.browserURLTemplate, prompt: Text("https://custom-ai.com/?q={text}"))
                        Text("Use **{text}** as a placeholder for the prompt and selection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!aiManager.isAIEnabled)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func fetchModels() {
        isFetchingModels = true
        fetchError = nil
        Task {
            do {
                let models = try await CloudAPIProvider.fetchAvailableModels(
                    apiKey: aiManager.cloudAPIKey,
                    provider: aiManager.cloudServiceProvider,
                    customBaseURL: aiManager.cloudCustomURL
                )
                await MainActor.run {
                    self.fetchedModels = models
                    self.isFetchingModels = false
                    if let first = models.first, !models.contains(aiManager.cloudModel) {
                        aiManager.cloudModel = first
                    }
                }
            } catch {
                await MainActor.run {
                    self.fetchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isFetchingModels = false
                }
            }
        }
    }
}
