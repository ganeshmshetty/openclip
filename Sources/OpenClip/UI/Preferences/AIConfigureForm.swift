// AIConfigureForm.swift
// OpenClip
//
// Reusable AI engine + provider configuration form, shared by the AI preferences
// tab and the first-launch onboarding flow so both surfaces expose the same settings.
import SwiftUI
import AppKit
import Core

@MainActor
public struct AIConfigureForm: View {
    /// `true` when the caller supplies the surrounding `Form` (AI preferences); `false` renders a self-contained form for onboarding.
    private let embedded: Bool

    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var fetchedCloudModels: [String] = []
    @State private var isFetchingCloudModels: Bool = false
    @State private var cloudFetchError: String? = nil
    @State private var cloudFetchGeneration: Int = 0
    @State private var cloudKeyDebounceTask: Task<Void, Never>?

    @State private var fetchedLocalModels: [String] = []
    @State private var isFetchingLocalModels: Bool = false
    @State private var localFetchError: String? = nil
    @State private var localFetchGeneration: Int = 0

    @State private var fetchedCLIModels: [String] = []
    @State private var isFetchingCLIModels: Bool = false

    @State private var cliReadiness: [CLIPreset: CLIReadiness] = [:]
    @State private var checkingCLI: Set<CLIPreset> = []
    @State private var cliReadinessGeneration = 0
    @State private var customReadinessTask: Task<Void, Never>?
    @State private var pendingSetupRefresh = false
    @State private var installingCLI: Set<CLIPreset> = []
    @State private var installError: String?

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        if embedded {
            sections
        } else {
            Form {
                sections
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var sections: some View {
        Group {
            Section(header: Text("Provider Settings")) {
                Picker("Select a Provider", selection: Binding(
                    get: { aiManager.activeProviderType.rawValue },
                    set: { newValue in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            aiManager.activeProviderRaw = newValue
                        }
                    }
                )) {
                    ForEach(availableProviders, id: \.1) { (label, value) in
                        Text(label).tag(value)
                    }
                }

                if AppleIntelligenceAvailability.isSupported && aiManager.activeProviderType == .apple {
                    let status = AppleIntelligenceAvailability.current
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "applelogo")
                                .font(.system(size: 14, weight: .medium))
                            Text("Apple Intelligence")
                                .font(.system(size: 13, weight: .medium))

                            HStack(spacing: 6) {
                                Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(status.isAvailable ? .green : .orange)
                                Text(AppleIntelligenceAvailability.statusLabel(for: status))
                                    .foregroundColor(status.isAvailable ? .secondary : .orange)
                            }
                            .font(.caption)
                        }

                        if !status.isAvailable {
                            Text(AppleIntelligenceAvailability.unavailableExplanation(for: status))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                        HStack(spacing: 4) {
                            Text("Status:")
                                .foregroundColor(.secondary)

                            Text(localFetchError)
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                        .padding(.vertical, 2)
                    }
                } else if aiManager.activeProviderType == .cli {
                    Picker("CLI Tool", selection: $aiManager.cliPreset) {
                        ForEach(CLIPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: aiManager.cliPreset) { _ in
                        fetchCLIModels()
                    }

                    if aiManager.cliPreset == .custom {
                        TextField("Execution Command", text: $aiManager.cliCustomCommand, prompt: Text("e.g. llm -m claude-3-5-sonnet"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: aiManager.cliCustomCommand) { _ in
                                scheduleCustomReadiness()
                            }

                        TextField("Auth Check Command (Optional)", text: $aiManager.cliCustomAuthCommand, prompt: Text("e.g. llm models or test probe command"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: aiManager.cliCustomAuthCommand) { _ in
                                scheduleCustomReadiness()
                            }

                        if let note = customCommandValidation {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Selected text will be piped to stdin with $OPENCLIP_PROMPT and $OPENCLIP_TEXT set.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        selectedCLIStatusRow

                        HStack(spacing: 8) {
                            Text("Model")
                            Spacer(minLength: 12)
                            SearchableModelPicker(
                                title: "Model",
                                selection: $aiManager.cliModel,
                                models: resolvedCLIModels,
                                customTag: "custom",
                                displayName: modelDisplayName
                            )

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
                            TextField("Custom Model Identifier", text: $aiManager.cliCustomModel, prompt: Text("Model id or alias"))
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
                        fetchedCloudModels = []
                        cloudFetchError = nil
                        refreshCloudModelsIfStale()
                    }

                    if aiManager.cloudServiceProvider == .custom {
                        TextField("Base Endpoint URL", text: $aiManager.cloudCustomURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    SecureField("API Key", text: $aiManager.cloudAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: aiManager.cloudAPIKey) { newKey in
                            cloudKeyDebounceTask?.cancel()
                            let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else {
                                cloudFetchGeneration += 1
                                isFetchingCloudModels = false
                                fetchedCloudModels = []
                                cloudFetchError = nil
                                return
                            }
                            cloudKeyDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                guard !Task.isCancelled else { return }
                                guard aiManager.activeProviderType == .cloud else { return }
                                fetchCloudModels()
                            }
                        }

                    HStack(spacing: 8) {
                        Text("Model")
                        Spacer(minLength: 12)
                        SearchableModelPicker(
                            title: "Model",
                            selection: $aiManager.cloudModel,
                            models: resolvedCloudModels,
                            customTag: "custom",
                            displayName: modelDisplayName
                        )

                        Button(action: fetchCloudModels) {
                            if isFetchingCloudModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch available models live from API")
                        .disabled(!canFetchCloudModels || isFetchingCloudModels)
                    }

                    if isCloudModelUnlisted {
                        Text("This model is not in the provider's current list. It may have been retired.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if aiManager.cloudModel == "custom" {
                        TextField("Custom Model Identifier", text: $aiManager.cloudCustomModel, prompt: Text("e.g. gpt-5-mini or claude-sonnet-5-5"))
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
        .onAppear {
            if aiManager.activeProviderType == .cli {
                refreshCLIReadiness()
                fetchCLIModels()
            } else if aiManager.activeProviderType == .local {
                fetchLocalModels()
            } else if aiManager.activeProviderType == .cloud {
                refreshCloudModelsIfStale()
            }
        }
        .onDisappear {
            cloudKeyDebounceTask?.cancel()
            customReadinessTask?.cancel()
        }
        .onChange(of: aiManager.activeProviderRaw) { newRaw in
            cloudKeyDebounceTask?.cancel()
            if newRaw == AIProviderType.cli.rawValue {
                refreshCLIReadiness()
                fetchCLIModels()
            } else if newRaw == AIProviderType.local.rawValue {
                fetchLocalModels()
            } else if newRaw == AIProviderType.cloud.rawValue {
                refreshCloudModelsIfStale()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notification in
            guard pendingSetupRefresh,
                  let app = notification.object as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            pendingSetupRefresh = false
            refreshCLIReadiness()
        }
        .alert("Install failed", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK", role: .cancel) { installError = nil }
        } message: {
            Text(installError ?? "")
        }
    }

    private var canFetchCloudModels: Bool {
        !aiManager.cloudAPIKey.isEmpty || aiManager.cloudServiceProvider == .openrouter
    }

    private func refreshCloudModelsIfStale() {
        guard canFetchCloudModels else { return }
        if let cached = CloudModelCatalog.cached(for: aiManager.cloudServiceProvider), CloudModelCatalog.isFresh(cached) { return }
        fetchCloudModels()
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
        let source = fetchedCLIModels.isEmpty ? aiManager.cliPreset.defaultModels : fetchedCLIModels
        var list = ["default"]
        for model in source where model != "default" && model != "custom" && !list.contains(model) {
            list.append(model)
        }
        if !aiManager.cliModel.isEmpty && aiManager.cliModel != "custom" && !list.contains(aiManager.cliModel) {
            list.append(aiManager.cliModel)
        }
        return list
    }

    private var resolvedCloudModels: [String] {
        let provider = aiManager.cloudServiceProvider
        return ["default"] + CloudModelCatalog.choices(
            live: fetchedCloudModels,
            cached: CloudModelCatalog.cached(for: provider),
            provider: provider,
            current: aiManager.cloudModel
        )
    }

    private var isCloudModelUnlisted: Bool {
        let model = aiManager.cloudModel
        guard !fetchedCloudModels.isEmpty, model != "default", model != "custom" else { return false }
        return !fetchedCloudModels.contains(model)
    }

    private func modelDisplayName(_ model: String) -> String {
        if model == "default" {
            return "Default"
        }
        return model
    }

    // MARK: - Actions

    /// Shown only after a custom command is entered, and only when that command does not check out.
    private var customCommandValidation: String? {
        let trimmed = aiManager.cliCustomCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !checkingCLI.contains(.custom) else { return nil }
        guard let status = cliReadiness[.custom], status.state != .ready, status.state != .unspecified else { return nil }
        return status.hint.isEmpty ? nil : status.hint
    }

    private var selectedCLIStatusRow: some View {
        let preset = aiManager.cliPreset
        let status = cliReadiness[preset]
        let checking = checkingCLI.contains(preset)
        let hasStatus = status?.showsStatus == true
        return HStack(spacing: 8) {
            if let status, hasStatus {
                Circle()
                    .fill(status.state == .ready ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(status.title)
                    .foregroundStyle(status.state == .ready ? Color.primary : Color.orange)
                    .lineLimit(1)
                    .layoutPriority(1)
                if status.state == .ready, let version = status.version, !version.isEmpty {
                    Text(version)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let title = status.setupActionTitle, let command = status.fixCommand {
                    if status.state == .notInstalled {
                        if installingCLI.contains(preset) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(title) {
                                installCLI(preset)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                            .help(Text(command))
                        }
                    } else {
                        Button(title) {
                            runInTerminal(command)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .help(Text(preset.authHelpText))
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            Button(action: refreshCLIReadiness) {
                if checking && hasStatus {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderless)
            .help("Re-check CLI status")
            .accessibilityLabel(Text("Re-check CLI status"))
            .disabled(checking)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func installCLI(_ preset: CLIPreset) {
        guard !installingCLI.contains(preset) else { return }
        installingCLI.insert(preset)
        Task {
            let result = await CLIProvider.install(preset)
            await MainActor.run {
                installingCLI.remove(preset)
                if result.succeeded {
                    CLIProvider.invalidateExecutableCache()
                    refreshCLIReadiness()
                } else {
                    let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    installError = trimmed.isEmpty ? String(localized: "Install failed") : String(trimmed.suffix(1_200))
                }
            }
        }
    }

    private func runInTerminal(_ command: String) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip-cli-\(UUID().uuidString).command")
        let script = """
        #!/bin/zsh
        \(command)
        status=$?
        echo
        if [ $status -eq 0 ]; then
            echo "Done."
        else
            echo "Command failed with exit code $status."
        fi
        echo "Press Return to close this window."
        read -r
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            pendingSetupRefresh = true
            NSWorkspace.shared.open(scriptURL)
        } catch {
            Log.presentation.error("Failed to run CLI setup command: \(error.localizedDescription)")
        }
    }

    private func scheduleCustomReadiness() {
        customReadinessTask?.cancel()
        let command = aiManager.cliCustomCommand
        let auth = aiManager.cliCustomAuthCommand
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cliReadiness[.custom] = .unspecified()
            checkingCLI.remove(.custom)
            return
        }
        checkingCLI.insert(.custom)
        customReadinessTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let status = await CLIProvider.readiness(for: .custom, customCommand: command, customAuthCommand: auth)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.aiManager.cliCustomCommand == command,
                      self.aiManager.cliCustomAuthCommand == auth else { return }
                self.cliReadiness[.custom] = status
                self.checkingCLI.remove(.custom)
            }
        }
    }

    private func refreshCLIReadiness() {
        CLIProvider.invalidateExecutableCache()
        cliReadinessGeneration += 1
        let generation = cliReadinessGeneration
        let presets = CLIPreset.allCases
        let customCmd = aiManager.cliCustomCommand
        let customAuthCmd = aiManager.cliCustomAuthCommand
        checkingCLI = Set(presets)
        Task {
            await withTaskGroup(of: (CLIPreset, CLIReadiness).self) { group in
                for preset in presets {
                    group.addTask {
                        let status = await CLIProvider.readiness(
                            for: preset,
                            customCommand: customCmd,
                            customAuthCommand: customAuthCmd
                        )
                        return (preset, status)
                    }
                }
                for await (preset, status) in group {
                    await MainActor.run {
                        guard self.cliReadinessGeneration == generation else { return }
                        if preset == .custom,
                           self.aiManager.cliCustomCommand != customCmd
                            || self.aiManager.cliCustomAuthCommand != customAuthCmd {
                            self.checkingCLI.remove(preset)
                            return
                        }
                        self.cliReadiness[preset] = status
                        self.checkingCLI.remove(preset)
                    }
                }
            }
        }
    }

    private func fetchCLIModels() {
        let preset = aiManager.cliPreset
        isFetchingCLIModels = true
        Task {
            let models = await CLIProvider.fetchAvailableModels(for: preset)
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
                    CloudModelCatalog.save(models, for: targetProvider)
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

    private var availableProviders: [(String, String)] {
        AIProviderType.supportedCases.map { type in
            let label: String
            switch type {
            case .apple: label = String(localized: "Apple")
            case .local: label = String(localized: "Local")
            case .cli: label = String(localized: "CLI")
            case .cloud: label = String(localized: "Cloud")
            }
            return (label, type.rawValue)
        }
    }
}

