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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Features")
                            .font(.headline)
                        Text("Show AI tools in the text selection popup bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Apple Intelligence (On-Device)", systemImage: "applelogo")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Uses native macOS Writing Tools & on-device models. Zero API key needed, 100% private.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ollama Server Endpoint")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("http://localhost:11434", text: $aiManager.ollamaURL)
                            .textFieldStyle(.roundedBorder)

                        Text("Model Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("llama3", text: $aiManager.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .browser {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Default Chatbot", selection: $aiManager.browserPreset) {
                            Text("ChatGPT (OpenAI)").tag("chatgpt")
                            Text("Claude (Anthropic)").tag("claude")
                            Text("Perplexity AI").tag("perplexity")
                            Text("Google Gemini").tag("gemini")
                            Text("DeepSeek").tag("deepseek")
                            Text("Custom URL...").tag("custom")
                        }

                        if aiManager.browserPreset == "custom" {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Web URL")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("https://custom-ai.com/?q={text}", text: $aiManager.browserURLTemplate)
                                    .textFieldStyle(.roundedBorder)
                                Text("Use **{text}** as a placeholder for the prompt and selection.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
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
