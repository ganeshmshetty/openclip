// CLIProvider.swift
// OpenClip
//
// AI text processing via local command-line tools (Claude Code, Codex CLI, GitHub Copilot, custom scripts).
// Leverages existing user terminal subscriptions with zero extra API key configuration.
import Foundation
import Core

public enum CLIPreset: String, CaseIterable, Identifiable, Sendable {
    case claude = "claude"
    case codex = "codex"
    case copilot = "copilot"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code (claude)"
        case .codex: return "Codex CLI (codex)"
        case .copilot: return "GitHub Copilot (gh copilot)"
        case .custom: return "Custom Command"
        }
    }

    public var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .copilot: return "gh"
        case .custom: return ""
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .claude:
            return ["default", "sonnet", "haiku", "opus", "claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"]
        case .codex:
            return ["default", "gpt-5.6-terra", "o3", "o3-mini", "o1", "gpt-4o", "gpt-4o-mini"]
        case .copilot:
            return ["default", "gpt-4o", "claude-3.5-sonnet", "o1"]
        case .custom:
            return ["default"]
        }
    }

    public var primaryModel: String {
        switch self {
        case .claude: return "sonnet"
        case .codex: return "gpt-5.6-terra"
        case .copilot: return "gpt-4o"
        case .custom: return "default"
        }
    }

    public var loginCommand: String {
        switch self {
        case .claude: return "claude auth login"
        case .codex: return "codex"
        case .copilot: return "gh auth login"
        case .custom: return ""
        }
    }

    public var authHelpText: String {
        switch self {
        case .claude:
            return "Run “claude auth login” in Terminal to sign in with your active Claude Pro, Team, or Max subscription."
        case .codex:
            return "Codex automatically detects your ChatGPT account or API credentials. To authenticate, launch “codex” in Terminal to sign in with your ChatGPT Plus, Team, or Enterprise subscription."
        case .copilot:
            return "Run “gh auth login” in Terminal to authenticate your GitHub account with GitHub Copilot access."
        case .custom:
            return "Custom CLI tools can authenticate via shell environment variables (e.g. API keys in ~/.zshrc), session credentials, or local execution without credentials."
        }
    }

    public var installationHint: String {
        switch self {
        case .claude:
            return "Install: npm install -g @anthropic-ai/claude-code"
        case .codex:
            return "Install: brew install codex"
        case .copilot:
            return "Install: brew install gh && gh extension install github/gh-copilot"
        case .custom:
            return "Specify any CLI command that accepts stdin or prompt arguments"
        }
    }
}

@MainActor
public final class CLIProvider: AIProvider {
    public var type: AIProviderType { .cli }

    public let preset: CLIPreset
    public let customCommand: String
    public let modelOverride: String

    public init(preset: CLIPreset, customCommand: String = "", modelOverride: String = "") {
        self.preset = preset
        self.customCommand = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelOverride = (trimmedModel.isEmpty || trimmedModel.lowercased() == "default") ? "" : trimmedModel
    }

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        let preset = self.preset
        let customCommand = self.customCommand
        let modelOverride = self.modelOverride

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let validated = try AIRequestSupport.validateInput(prompt: prompt, text: text)
                    let hasInputText = !validated.text.isEmpty
                    let systemInstruction = AIRequestSupport.systemPrompt(for: validated.prompt, hasInputText: hasInputText)
                    let userContent = AIRequestSupport.userContent(for: validated.text, fallbackPrompt: validated.prompt)

                    let invocation = try Self.buildInvocation(
                        preset: preset,
                        systemPrompt: systemInstruction,
                        userContent: userContent,
                        customCommand: customCommand,
                        modelOverride: modelOverride
                    )

                    try await Self.runStreamingProcess(invocation: invocation, preset: preset, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Binary Resolution

    nonisolated public static func resolveBinaryPath(for binary: String) -> String? {
        let trimmed = binary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Direct path check if path is absolute
        if trimmed.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
        }

        // 2. Common macOS installation paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standardCandidates = [
            "\(home)/.local/bin/\(trimmed)",
            "/opt/homebrew/bin/\(trimmed)",
            "/usr/local/bin/\(trimmed)",
            "\(home)/.cargo/bin/\(trimmed)",
            "/usr/bin/\(trimmed)",
            "/bin/\(trimmed)"
        ]

        for path in standardCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. Login shell fallback via 'which'
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(trimmed)"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                return output
            }
        }

        return nil
    }

    nonisolated public static func inspectConfiguredModel(for preset: CLIPreset) -> String? {
        switch preset {
        case .codex:
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let configPath = "\(home)/.codex/config.toml"
            if let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("model") && trimmed.contains("=") {
                        let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            var val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"\'"))
                            if !val.isEmpty { return val }
                        }
                    }
                }
            }
            return nil
        default:
            return nil
        }
    }

    nonisolated public static func fetchAvailableModels(for preset: CLIPreset) async throws -> [String] {
        switch preset {
        case .claude:
            guard resolveBinaryPath(for: "claude") != nil else {
                throw AIError.providerUnavailable("Claude Code CLI not installed")
            }
            return ["sonnet", "haiku", "opus", "claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"]

        case .codex:
            guard resolveBinaryPath(for: "codex") != nil else {
                throw AIError.providerUnavailable("Codex CLI not installed")
            }
            var models = ["gpt-5.6-terra", "o3", "o3-mini", "o1", "gpt-4o", "gpt-4o-mini"]
            if let configured = inspectConfiguredModel(for: .codex), !models.contains(configured) {
                models.insert(configured, at: 0)
            }
            return models

        case .copilot:
            guard resolveBinaryPath(for: "gh") != nil else {
                throw AIError.providerUnavailable("GitHub CLI not installed")
            }
            return ["gpt-4o", "claude-3.5-sonnet", "o1"]

        case .custom:
            return []
        }
    }

    nonisolated public static func checkAuthStatus(
        for preset: CLIPreset,
        customCommand: String = "",
        customAuthCommand: String = ""
    ) async -> (isAuthenticated: Bool, message: String) {
        if preset == .custom {
            let authCmd = customAuthCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !authCmd.isEmpty {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", authCmd]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    return (process.terminationStatus == 0, process.terminationStatus == 0 ? "Authenticated" : "Auth Failed")
                } catch {
                    return (false, "Auth Failed")
                }
            }

            let execCmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if execCmd.isEmpty {
                return (false, "Command Required")
            }
            let firstWord = execCmd.components(separatedBy: .whitespaces).first ?? ""
            if resolveBinaryPath(for: firstWord) != nil {
                return (true, "Executable Ready")
            }
            return (false, "Not Found")
        }

        guard let binaryPath = resolveBinaryPath(for: preset.binaryName) else {
            return (false, "Not Installed")
        }

        switch preset {
        case .claude:
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(binaryPath) auth status"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if output.contains("\"loggedIn\": true") || output.contains("\"loggedIn\":true") {
                    return (true, "Authenticated")
                } else if output.contains("\"loggedIn\": false") || output.contains("\"loggedIn\":false") {
                    return (false, "Not Authenticated")
                }
                return (process.terminationStatus == 0, process.terminationStatus == 0 ? "Authenticated" : "Not Authenticated")
            } catch {
                return (false, "Not Authenticated")
            }

        case .codex:
            let pipe = Pipe()
            let errPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(binaryPath) login status"]
            process.standardOutput = pipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
                if process.terminationStatus == 0 && output.localizedCaseInsensitiveContains("logged in") && !output.localizedCaseInsensitiveContains("not logged in") {
                    return (true, "Authenticated")
                }
                return (false, "Not Authenticated")
            } catch {
                return (false, "Not Authenticated")
            }

        case .copilot:
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(binaryPath) auth status"]
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return (true, "Authenticated")
                }
                return (false, "Not Authenticated")
            } catch {
                return (false, "Not Authenticated")
            }

        case .custom:
            return (true, "Ready")
        }
    }

    nonisolated public static func detectionStatus(for preset: CLIPreset, customCommand: String = "") -> (isFound: Bool, details: String) {
        if preset == .custom {
            let cmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if cmd.isEmpty {
                return (false, "Enter a command")
            }
            let firstWord = cmd.components(separatedBy: .whitespaces).first ?? ""
            if let path = resolveBinaryPath(for: firstWord) {
                return (true, "Executable found at \(path)")
            }
            return (false, "Binary “\(firstWord)” not found")
        }

        let binary = preset.binaryName
        if let path = resolveBinaryPath(for: binary) {
            return (true, "Found at \(path)")
        }
        return (false, preset.installationHint)
    }

    // MARK: - Invocation Building

    private struct ProcessInvocation: Sendable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let stdinText: String?
    }

    nonisolated private static func buildInvocation(
        preset: CLIPreset,
        systemPrompt: String,
        userContent: String,
        customCommand: String,
        modelOverride: String
    ) throws -> ProcessInvocation {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.cargo/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        switch preset {
        case .claude:
            guard let binary = resolveBinaryPath(for: "claude") else {
                throw AIError.providerUnavailable("Claude Code CLI ('claude') not found. \(CLIPreset.claude.installationHint)")
            }
            var args = ["-p", "--tools", "", "--no-session-persistence", "--system-prompt", systemPrompt]
            if !modelOverride.isEmpty {
                args.append(contentsOf: ["--model", modelOverride])
            }
            return ProcessInvocation(
                executableURL: URL(fileURLWithPath: binary),
                arguments: args,
                environment: env,
                stdinText: userContent
            )

        case .codex:
            guard let binary = resolveBinaryPath(for: "codex") else {
                throw AIError.providerUnavailable("Codex CLI ('codex') not found. \(CLIPreset.codex.installationHint)")
            }
            var args = [
                "exec",
                systemPrompt,
                "--skip-git-repo-check",
                "--ephemeral",
                "--sandbox",
                "read-only",
                "--json"
            ]
            if !modelOverride.isEmpty {
                args.append(contentsOf: ["-m", modelOverride])
            }
            return ProcessInvocation(
                executableURL: URL(fileURLWithPath: binary),
                arguments: args,
                environment: env,
                stdinText: userContent
            )

        case .copilot:
            guard let binary = resolveBinaryPath(for: "gh") else {
                throw AIError.providerUnavailable("GitHub CLI ('gh') not found. \(CLIPreset.copilot.installationHint)")
            }
            let fullInstruction = "\(systemPrompt)\n\n\(userContent)"
            return ProcessInvocation(
                executableURL: URL(fileURLWithPath: binary),
                arguments: ["copilot", "-p", fullInstruction],
                environment: env,
                stdinText: nil
            )

        case .custom:
            guard !customCommand.isEmpty else {
                throw AIError.providerUnavailable("Custom CLI command is empty. Configure it in Preferences → AI.")
            }
            env["OPENCLIP_PROMPT"] = systemPrompt
            env["OPENCLIP_TEXT"] = userContent
            return ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-l", "-c", customCommand],
                environment: env,
                stdinText: userContent
            )
        }
    }

    // MARK: - Process Execution

    nonisolated private static func runStreamingProcess(
        invocation: ProcessInvocation,
        preset: CLIPreset,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.environment = invocation.environment

        let stdOutPipe = Pipe()
        let stdErrPipe = Pipe()
        let stdInPipe = Pipe()
        process.standardOutput = stdOutPipe
        process.standardError = stdErrPipe
        process.standardInput = stdInPipe

        let outAccumulator = LineStreamAccumulator(handle: stdOutPipe.fileHandleForReading) { line in
            if let parsed = parseOutputLine(line, preset: preset), !parsed.isEmpty {
                continuation.yield(parsed)
            }
        }
        let errAccumulator = StderrAccumulator(handle: stdErrPipe.fileHandleForReading)

        outAccumulator.start()
        errAccumulator.start()

        try await withTaskCancellationHandler {
            do {
                try process.run()

                if let stdinText = invocation.stdinText, let data = stdinText.data(using: .utf8) {
                    try? stdInPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try? stdInPipe.fileHandleForWriting.close()

                process.waitUntilExit()

                outAccumulator.finish()
                let errStr = errAccumulator.finish().trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus != 0 {
                    let message = errStr.isEmpty ? "CLI process exited with code \(process.terminationStatus)" : errStr
                    continuation.finish(throwing: AIError.providerUnavailable(message))
                    return
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        } onCancel: {
            ShellProcessRunner.terminateProcessGroup(process)
        }
    }

    nonisolated private static func parseOutputLine(_ line: String, preset: CLIPreset) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch preset {
        case .codex:
            guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else {
                return nil
            }
            guard let data = trimmed.data(using: .utf8) else { return nil }

            struct CodexEvent: Decodable {
                let type: String?
                struct Item: Decodable {
                    let type: String?
                    let text: String?
                }
                struct TurnError: Decodable {
                    let message: String?
                }
                let item: Item?
                let delta: String?
                let error: TurnError?
                let message: String?
            }

            if let event = try? JSONDecoder().decode(CodexEvent.self, from: data) {
                if let text = event.item?.text, !text.isEmpty {
                    return text
                }
                if let delta = event.delta, !delta.isEmpty {
                    return delta
                }
                if event.type == "turn.failed", let errMsg = event.error?.message, !errMsg.isEmpty {
                    return "\n[Error: \(errMsg)]"
                }
            }
            return nil

        case .claude, .copilot, .custom:
            return line + "\n"
        }
    }
}

// MARK: - Thread-safe Accumulators

private final class LineStreamAccumulator: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var lineBuffer = ""
    private let onLine: @Sendable (String) -> Void

    init(handle: FileHandle, onLine: @escaping @Sendable (String) -> Void) {
        self.handle = handle
        self.onLine = onLine
    }

    func start() {
        handle.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let available = fh.availableData
            guard !available.isEmpty, let chunk = String(data: available, encoding: .utf8) else { return }

            var linesToEmit: [String] = []
            self.lock.lock()
            self.lineBuffer += chunk
            while let newlineIndex = self.lineBuffer.firstIndex(of: "\n") {
                let line = String(self.lineBuffer[..<newlineIndex])
                self.lineBuffer = String(self.lineBuffer[self.lineBuffer.index(after: newlineIndex)...])
                linesToEmit.append(line)
            }
            self.lock.unlock()

            for line in linesToEmit {
                self.onLine(line)
            }
        }
    }

    func finish() {
        handle.readabilityHandler = nil
        lock.lock()
        let remaining = lineBuffer
        lineBuffer = ""
        lock.unlock()
        if !remaining.isEmpty {
            onLine(remaining)
        }
    }
}

private final class StderrAccumulator: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        handle.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let available = fh.availableData
            guard !available.isEmpty else { return }
            self.lock.lock()
            self.data.append(available)
            self.lock.unlock()
        }
    }

    func finish() -> String {
        handle.readabilityHandler = nil
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
