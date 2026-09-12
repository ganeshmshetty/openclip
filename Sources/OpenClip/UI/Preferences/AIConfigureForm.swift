// AIConfigureForm.swift
// OpenClip
//
// Reusable AI engine + provider configuration form, shared by the AI preferences
// tab and the first-launch onboarding flow so both surfaces expose the same settings.
import SwiftUI
import AppKit

@MainActor
public struct AIConfigureForm: View {
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var fetchedCloudModels: [String] = []
    @State private var isFetchingCloudModels: Bool = false
    @State private var cloudFetchError: String? = nil
    @State private var cloudFetchGeneration: Int = 0

    @State private var fetchedLocalModels: [String] = []
    @State private var isFetchingLocalModels: Bool = false
    @State private var localFetchError: String? = nil
    @State private var localFetchGeneration: Int = 0

    @State private var fetchedCLIModels: [String] = []
    @State private var isFetchingCLIModels: Bool = false

    @State private var cliAuthStatus: (isAuthenticated: Bool, message: String)? = nil
    @State private var isCheckingCLIAuth: Bool = false
    @State private var showingAuthInfoPopover: Bool = false

    public init() {}

    public var body: some View {
        Form {
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
                    Text("Local").tag(AIProviderType.local.rawValue)
                    Text("CLI").tag(AIProviderType.cli.rawValue)
                    Text("Cloud").tag(AIProviderType.cloud.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(header: Text("Provider Settings")) {
                if aiManager.activeProviderType == .apple {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 14, weight: .medium))
                        Text("Apple Intelligence (On-Device)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .local {
                    Picker("Server Type", selection: $aiManager.localPreset) {
                        ForEach(LocalLLMPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: aiManager.localPreset) { _ in
                        fetchLocalModels()
                    }

                    TextField("Server Endpoint", text: $aiManager.localURL, prompt: Text(aiManager.localPreset.defaultBaseURL))
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Picker("Model", selection: $aiManager.localModel) {
                            ForEach(resolvedLocalModels, id: \.self) { m in
                                Text(modelDisplayName(m)).tag(m)
                            }
                            Text("Custom…").tag("custom")
                        }

                        Button(action: fetchLocalModels) {
                            if isFetchingLocalModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch loaded models from local server")
                        .disabled(isFetchingLocalModels)
                    }

                    if aiManager.localModel == "custom" {
                        TextField("Custom Model Name", text: $aiManager.localCustomModel, prompt: Text("e.g. qwen2.5-coder-7b-instruct"))
                            .textFieldStyle(.roundedBorder)
                    }

                    if let localFetchError {
                        Text("Connection failed: \(localFetchError)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else if aiManager.activeProviderType == .cli {
                    Picker("CLI Tool", selection: $aiManager.cliPreset) {
                        ForEach(CLIPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: aiManager.cliPreset) { _ in
                        checkCLIAuth()
                        fetchCLIModels()
                    }

                    // Authentication Status Row
                    HStack(spacing: 6) {
                        Text("Status:")
                            .foregroundColor(.secondary)

                        if isCheckingCLIAuth {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                                .foregroundColor(.secondary)
                        } else if let status = cliAuthStatus {
                            Image(systemName: status.isAuthenticated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(status.isAuthenticated ? .green : .orange)
                            Text(status.message)
                                .foregroundColor(status.isAuthenticated ? .primary : .orange)
                        } else {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                                .foregroundColor(.secondary)
                        }

                        Button {
                            showingAuthInfoPopover = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("How to authenticate")
                        .popover(isPresented: $showingAuthInfoPopover) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Authentication")
                                    .font(.headline)
                                Text(authHelpText)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)

                                if aiManager.cliPreset == .codex {
                                    Button("Open Terminal") {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else if !aiManager.cliPreset.loginCommand.isEmpty {
                                    Button("Copy Terminal Command") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(aiManager.cliPreset.loginCommand, forType: .string)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(14)
                            .frame(width: 280)
                        }

                        Spacer()

                        Button(action: checkCLIAuth) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderless)
                        .help("Re-check authentication status")
                        .disabled(isCheckingCLIAuth)
                    }
                    .font(.caption)
                    .padding(.vertical, 2)

                    if aiManager.cliPreset == .custom {
                        TextField("Execution Command", text: $aiManager.cliCustomCommand, prompt: Text("e.g. llm -m claude-3-5-sonnet"))
                            .textFieldStyle(.roundedBorder)

                        TextField("Auth Check Command (Optional)", text: $aiManager.cliCustomAuthCommand, prompt: Text("e.g. llm models or test probe command"))
                            .textFieldStyle(.roundedBorder)

                        Text("Selected text will be piped to stdin with $OPENCLIP_PROMPT and $OPENCLIP_TEXT set.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Picker("Model", selection: $aiManager.cliModel) {
                                ForEach(resolvedCLIModels, id: \.self) { m in
                                    Text(modelDisplayName(m)).tag(m)
                                }
                                Text("Custom…").tag("custom")
                            }

                            Button(action: fetchCLIModels) {
                                if isFetchingCLIModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderless)
                            .help("Detect available models from CLI")
                            .disabled(isFetchingCLIModels)
                        }

                        if aiManager.cliModel == "custom" {
                            TextField("Custom Model Identifier", text: $aiManager.cliCustomModel, prompt: Text("e.g. claude-3-7-sonnet-20250219 or o3-mini"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else if aiManager.activeProviderType == .cloud {
                    Picker("Service Provider", selection: $aiManager.cloudServiceProvider) {
                        ForEach(CloudServiceProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: aiManager.cloudServiceProvider) { _ in
                        fetchCloudModels()
                    }

                    if aiManager.cloudServiceProvider == .custom {
                        TextField("Base Endpoint URL", text: $aiManager.cloudCustomURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    SecureField("API Key", text: $aiManager.cloudAPIKey)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Picker("Model", selection: $aiManager.cloudModel) {
                            ForEach(resolvedCloudModels, id: \.self) { m in
                                Text(modelDisplayName(m)).tag(m)
                            }
                            Text("Custom…").tag("custom")
                        }

                        Button(action: fetchCloudModels) {
                            if isFetchingCloudModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch available models live from API")
                        .disabled(aiManager.cloudAPIKey.isEmpty || isFetchingCloudModels)
                    }

                    if aiManager.cloudModel == "custom" {
                        TextField("Custom Model Identifier", text: $aiManager.cloudCustomModel, prompt: Text("e.g. gpt-4o-2024-08-06 or claude-3-5-sonnet-latest"))
                            .textFieldStyle(.roundedBorder)
                    }

                    if let cloudFetchError {
                        Text("Query failed: \(cloudFetchError)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .disabled(!aiManager.isAIEnabled)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            if aiManager.activeProviderType == .cli {
                checkCLIAuth()
                fetchCLIModels()
            } else if aiManager.activeProviderType == .local {
                fetchLocalModels()
            } else if aiManager.activeProviderType == .cloud && !aiManager.cloudAPIKey.isEmpty {
                fetchCloudModels()
            }
        }
        .onChange(of: aiManager.activeProviderRaw) { newRaw in
            if newRaw == AIProviderType.cli.rawValue {
                checkCLIAuth()
                fetchCLIModels()
            } else if newRaw == AIProviderType.local.rawValue {
                fetchLocalModels()
            } else if newRaw == AIProviderType.cloud.rawValue && !aiManager.cloudAPIKey.isEmpty {
                fetchCloudModels()
            }
        }
    }

    // MARK: - Intelligent Model Resolution

    private var resolvedLocalModels: [String] {
        if fetchedLocalModels.isEmpty {
            let primary = aiManager.localPreset.primaryModel
            var list = ["default"]
            if primary != "default" {
                list.append(primary)
            }
            if !aiManager.localModel.isEmpty && aiManager.localModel != "custom" && !list.contains(aiManager.localModel) {
                list.append(aiManager.localModel)
            }
            return list
        } else {
            var list = ["default"]
            for m in fetchedLocalModels where m != "default" {
                list.append(m)
            }
            return list
        }
    }

    private var resolvedCLIModels: [String] {
        if fetchedCLIModels.isEmpty {
            let primary = CLIProvider.inspectConfiguredModel(for: aiManager.cliPreset) ?? aiManager.cliPreset.primaryModel
            var list = ["default"]
            if primary != "default" {
                list.append(primary)
            }
            if !aiManager.cliModel.isEmpty && aiManager.cliModel != "custom" && !list.contains(aiManager.cliModel) {
                list.append(aiManager.cliModel)
            }
            return list
        } else {
            var list = ["default"]
            for m in fetchedCLIModels where m != "default" {
                list.append(m)
            }
            return list
        }
    }

    private var resolvedCloudModels: [String] {
        if fetchedCloudModels.isEmpty {
            let primary = aiManager.cloudServiceProvider.primaryModel
            var list = ["default"]
            if primary != "default" {
                list.append(primary)
            }
            if !aiManager.cloudModel.isEmpty && aiManager.cloudModel != "custom" && !list.contains(aiManager.cloudModel) {
                list.append(aiManager.cloudModel)
            }
            return list
        } else {
            var list = ["default"]
            for m in fetchedCloudModels where m != "default" {
                list.append(m)
            }
            return list
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        if model == "default" {
            return "Default"
        }
        return model
    }

    private var authHelpText: String {
        if aiManager.cliPreset == .custom {
            return "Custom CLI tools can authenticate via shell environment variables (e.g. API keys in ~/.zshrc), session credentials, or local execution without credentials. You can optionally specify an Auth Check Command to verify that your tool is ready."
        }
        return aiManager.cliPreset.authHelpText
    }

    // MARK: - Actions

    private func checkCLIAuth() {
        isCheckingCLIAuth = true
        let preset = aiManager.cliPreset
        let customCmd = aiManager.cliCustomCommand
        let customAuthCmd = aiManager.cliCustomAuthCommand
        Task {
            let result = await CLIProvider.checkAuthStatus(for: preset, customCommand: customCmd, customAuthCommand: customAuthCmd)
            await MainActor.run {
                guard aiManager.cliPreset == preset else { return }
                self.cliAuthStatus = result
                self.isCheckingCLIAuth = false
            }
        }
    }

    private func fetchCLIModels() {
        let preset = aiManager.cliPreset
        isFetchingCLIModels = true
        Task {
            let models = (try? await CLIProvider.fetchAvailableModels(for: preset)) ?? []
            await MainActor.run {
                guard aiManager.cliPreset == preset else { return }
                self.fetchedCLIModels = models
                self.isFetchingCLIModels = false
            }
        }
    }

    private func fetchCloudModels() {
        cloudFetchGeneration += 1
        let currentGeneration = cloudFetchGeneration
        let targetProvider = aiManager.cloudServiceProvider
        let targetCustomURL = aiManager.cloudCustomURL
        let targetAPIKey = aiManager.cloudAPIKey

        isFetchingCloudModels = true
        cloudFetchError = nil
        Task {
            do {
                let models = try await CloudAPIProvider.fetchAvailableModels(
                    apiKey: targetAPIKey,
                    provider: targetProvider,
                    customBaseURL: targetCustomURL
                )
                await MainActor.run {
                    guard currentGeneration == self.cloudFetchGeneration,
                          aiManager.cloudServiceProvider == targetProvider,
                          aiManager.cloudCustomURL == targetCustomURL,
                          aiManager.cloudAPIKey == targetAPIKey else {
                        return
                    }
                    self.fetchedCloudModels = models
                    self.isFetchingCloudModels = false
                    if let first = models.first, !models.contains(aiManager.cloudModel), aiManager.cloudModel != "default", aiManager.cloudModel != "custom" {
                        aiManager.cloudModel = first
                    }
                }
            } catch {
                await MainActor.run {
                    guard currentGeneration == self.cloudFetchGeneration,
                          aiManager.cloudServiceProvider == targetProvider,
                          aiManager.cloudCustomURL == targetCustomURL,
                          aiManager.cloudAPIKey == targetAPIKey else {
                        return
                    }
                    self.cloudFetchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.fetchedCloudModels = []
                    self.isFetchingCloudModels = false
                }
            }
        }
    }

    private func fetchLocalModels() {
        localFetchGeneration += 1
        let currentGeneration = localFetchGeneration
        let targetURL = aiManager.localURL

        isFetchingLocalModels = true
        localFetchError = nil
        Task {
            do {
                let models = try await LocalLLMProvider.fetchAvailableModels(baseURL: targetURL)
                await MainActor.run {
                    guard currentGeneration == self.localFetchGeneration,
                          aiManager.localURL == targetURL else {
                        return
                    }
                    self.fetchedLocalModels = models
                    self.isFetchingLocalModels = false
                    if let first = models.first, !models.contains(aiManager.localModel), aiManager.localModel != "default", aiManager.localModel != "custom" {
                        aiManager.localModel = first
                    }
                }
            } catch {
                await MainActor.run {
                    guard currentGeneration == self.localFetchGeneration,
                          aiManager.localURL == targetURL else {
                        return
                    }
                    self.localFetchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.fetchedLocalModels = []
                    self.isFetchingLocalModels = false
                }
            }
        }
    }
}
