// AITab.swift
// OpenClip
//
// Renders the AI preferences view with top-bar sub-tab switching between AI Engine Configuration and AI Actions Management.
import SwiftUI

public enum AISubTab: String, CaseIterable, Identifiable, Sendable {
    case configure = "Configure"
    case actions = "Actions"
    public var id: String { rawValue }
}

@MainActor
public struct AITab: View {
    @Binding var selectedSubTab: AISubTab
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var fetchError: String? = nil

    @State private var editingPreset: AIActionPreset? = nil
    @State private var showingAddPresetSheet = false
    @State private var newTitle: String = ""
    @State private var newPrompt: String = ""
    
    public init(selectedSubTab: Binding<AISubTab> = .constant(.configure)) {
        self._selectedSubTab = selectedSubTab
    }
    
    public var body: some View {
        Group {
            switch selectedSubTab {
            case .configure:
                configureView
            case .actions:
                actionsView
            }
        }
    }

    // MARK: - Configure View
    private var configureView: some View {
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
        .padding(12)
    }

    // MARK: - Actions View
    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section(header: HStack {
                    Text("Configured AI Actions")
                    Spacer()
                    Button("Reset Defaults") {
                        aiManager.resetPresetsToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enable or disable AI actions for the popup bar, or click the edit icon to customize prompts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)

                        ForEach(aiManager.presets) { preset in
                            HStack(alignment: .center, spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { preset.isEnabled },
                                    set: { newValue in
                                        var updated = preset
                                        updated.isEnabled = newValue
                                        aiManager.updatePreset(updated)
                                    }
                                ))
                                .labelsHidden()

                                Text(preset.title)
                                    .font(.system(size: 13, weight: .medium))

                                Spacer()

                                Button(action: {
                                    editingPreset = preset
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit Action Prompt")
                            }
                            .padding(.vertical, 4)

                            if preset.id != aiManager.presets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button(action: {
                    showingAddPresetSheet = true
                }) {
                    Label("Add Custom AI Action", systemImage: "plus.circle")
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(item: $editingPreset) { preset in
            EditAIPresetSheet(preset: preset) { updated in
                aiManager.updatePreset(updated)
            }
        }
        .sheet(isPresented: $showingAddPresetSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Custom AI Action")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Action Title")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Simplify", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Instruction")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Rewrite text using simple 5th-grade vocabulary", text: $newPrompt)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    Button("Add Action") {
                        let id = "custom_\(UUID().uuidString.prefix(8))"
                        let preset = AIActionPreset(id: id, title: newTitle.trimmingCharacters(in: .whitespaces), prompt: newPrompt.trimmingCharacters(in: .whitespaces), isEnabled: true)
                        aiManager.updatePreset(preset)
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
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

struct EditAIPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preset: AIActionPreset
    let onSave: (AIActionPreset) -> Void

    @State private var title: String
    @State private var prompt: String

    init(preset: AIActionPreset, onSave: @escaping (AIActionPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        _title = State(initialValue: preset.title)
        _prompt = State(initialValue: preset.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit AI Action")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Action Title")
                    .font(.caption)
                    .fontWeight(.medium)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt Instruction")
                    .font(.caption)
                    .fontWeight(.medium)
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    var updated = preset
                    updated.title = title.trimmingCharacters(in: .whitespaces)
                    updated.prompt = prompt.trimmingCharacters(in: .whitespaces)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
