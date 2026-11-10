// CLIProvider.swift
// OpenClip
//
// AI text processing via local command-line tools. Preset details live in CLIToolCatalog.
import Foundation
import Core

/// Result of an install command run by the settings UI.
public struct CLIInstallResult: Sendable {
    public let succeeded: Bool
    public let output: String

    public init(succeeded: Bool, output: String) {
        self.succeeded = succeeded
        self.output = output
    }
}

@MainActor
public final class CLIProvider: AIProvider {
    public var type: AIProviderType { .cli }
    public let preset: CLIPreset
    public let customCommand: String
    public let modelOverride: String
    /// Replacement for the system prompt's role and behavior rules (Settings → AI → System Prompt);
    /// nil uses the built-in text.
    public let customGuidelines: String?

    public init(preset: CLIPreset, customCommand: String = "", modelOverride: String = "", customGuidelines: String? = nil) {
        self.customGuidelines = customGuidelines
        self.preset = preset
        self.customCommand = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelOverride = (trimmedModel.isEmpty || trimmedModel.lowercased() == "default") ? "" : trimmedModel
    }

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        let preset = self.preset
        let customCommand = self.customCommand
        let modelOverride = self.modelOverride
        let customGuidelines = self.customGuidelines

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let validated = try AIRequestSupport.validateInput(prompt: prompt, text: text)
                    let hasInputText = !validated.text.isEmpty
                    let systemInstruction = AIRequestSupport.systemPrompt(for: validated.prompt, hasInputText: hasInputText, customGuidelines: customGuidelines)
                    let userContent = AIRequestSupport.userContent(for: validated.text, fallbackPrompt: validated.prompt)

                    let invocation = try Self.buildInvocation(
                        preset: preset,
                        systemPrompt: systemInstruction,
                        userContent: userContent,
                        customCommand: customCommand,
                        modelOverride: modelOverride
                    )

                    try await Self.runStreamingProcess(invocation: invocation, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Status

    nonisolated public static func readiness(
        for preset: CLIPreset,
        customCommand: String = "",
        customAuthCommand: String = ""
    ) async -> CLIReadiness {
        await Task.detached(priority: .utility) {
            readinessBlocking(for: preset, customCommand: customCommand, customAuthCommand: customAuthCommand)
        }.value
    }

    nonisolated private static func readinessBlocking(
        for preset: CLIPreset,
        customCommand: String,
        customAuthCommand: String
    ) -> CLIReadiness {
        if preset == .custom {
            return customReadiness(command: customCommand, authCommand: customAuthCommand)
        }
        guard let tool = CLITool.tool(for: preset) else {
            return .notInstalled(command: "")
        }
        guard let binary = resolveBinary(in: tool.binaries) else {
            return CLIReadinessPlan.builtin(binaryFound: false, version: nil, authenticated: false, tool: tool)
        }
        let version = versionString(binary: binary, arguments: tool.versionArguments)
        let authenticated = evaluate(tool.auth, presetBinary: binary)
        return CLIReadinessPlan.builtin(binaryFound: true, version: version, authenticated: authenticated, tool: tool)
    }

    nonisolated private static func customReadiness(command: String, authCommand: String) -> CLIReadiness {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return CLIReadinessPlan.custom(command: "", binaryFound: false, authCommand: "", authPassed: false)
        }
        let firstWord = cmd.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let binaryFound = resolveBinaryPath(for: firstWord) != nil
        let auth = authCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let authPassed: Bool
        if !binaryFound || auth.isEmpty {
            authPassed = false
        } else {
            let shell = loginShellExecutable()
            let result = runCaptured(
                executable: shell,
                arguments: ["-l", "-c", auth],
                timeout: 8,
                environment: .inherit
            )
            authPassed = !result.timedOut && result.exitCode == 0
        }
        return CLIReadinessPlan.custom(command: cmd, binaryFound: binaryFound, authCommand: auth, authPassed: authPassed)
    }

    nonisolated private static func versionString(binary: String, arguments: [String]) -> String? {
        let result = runCaptured(executable: binary, arguments: arguments, timeout: 4)
        guard !result.timedOut, result.exitCode == 0 else { return nil }
        let line = result.stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line, !line.isEmpty else { return nil }
        return line.count > 80 ? String(line.prefix(80)) : line
    }

    nonisolated private static func evaluate(_ check: CLIAuthCheck, presetBinary: String) -> Bool {
        switch check {
        case .any(let checks):
            return checks.contains { evaluate($0, presetBinary: presetBinary) }
        case .environmentNonEmpty(let keys):
            let env = ProcessInfo.processInfo.environment
            return keys.contains { key in
                let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !value.isEmpty
            }
        case .keychainService(let service):
            let result = runCaptured(
                executable: "/usr/bin/security",
                arguments: ["find-generic-password", "-s", service],
                timeout: 3
            )
            return !result.timedOut && result.exitCode == 0
        case .homeRelativeFile(let relative):
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path)
        case .command(let binaryName, let arguments, let rule):
            let binary: String?
            if let binaryName {
                binary = resolveBinaryPath(for: binaryName)
            } else {
                binary = presetBinary
            }
            guard let binary, !binary.isEmpty else { return false }
            let result = runCaptured(executable: binary, arguments: arguments, timeout: 8)
            if result.timedOut { return false }
            return CLIAuthOutput.passes(rule: rule, exitCode: result.exitCode, output: result.stdout + result.stderr)
        }
    }

    nonisolated public static func inspectConfiguredModel(for preset: CLIPreset) -> String? {
        guard let tool = CLITool.tool(for: preset) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch tool.models {
        case .codexConfig:
            let configPath = "\(home)/.codex/config.toml"
            guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("model"), trimmed.contains("=") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
            return nil
        case .copilotConfig:
            let configDir = ProcessInfo.processInfo.environment["COPILOT_HOME"] ?? home + "/.copilot"
            let settingsPath = configDir + "/settings.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)) else { return nil }
            return copilotModel(fromSettingsData: data)
        case .none, .command:
            return nil
        }
    }

    nonisolated static func copilotModel(fromSettingsData data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = object["model"] as? String else { return nil }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated public static func fetchAvailableModels(for preset: CLIPreset) async -> [String] {
        await Task.detached(priority: .utility) {
            fetchAvailableModelsBlocking(for: preset)
        }.value
    }

    /// Runs the catalog's install command through the login shell, so Homebrew and npm see the
    /// same PATH the readiness check uses.
    nonisolated public static func install(_ preset: CLIPreset) async -> CLIInstallResult {
        guard let tool = CLITool.tool(for: preset) else {
            return CLIInstallResult(succeeded: false, output: "No install command is available for this CLI.")
        }
        return await Task.detached(priority: .userInitiated) {
            let result = runCaptured(
                executable: loginShellExecutable(),
                arguments: ["-l", "-c", tool.installCommand],
                timeout: 600,
                environment: .inherit
            )
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.timedOut {
                return CLIInstallResult(succeeded: false, output: "Installation timed out after 10 minutes.")
            }
            return CLIInstallResult(
                succeeded: result.exitCode == 0,
                output: stderr.isEmpty ? stdout : stderr
            )
        }.value
    }

    nonisolated private static func fetchAvailableModelsBlocking(for preset: CLIPreset) -> [String] {
        guard let tool = CLITool.tool(for: preset) else { return [] }
        let configured = inspectConfiguredModel(for: preset)
        let discovered = discoverModels(tool.models, tool: tool)
        return discovered.isEmpty ? fallbackModels(tool, configured: configured) : discovered
    }

    nonisolated private static func discoverModels(_ check: CLIModelCheck, tool: CLITool) -> [String] {
        switch check {
        case .none, .codexConfig, .copilotConfig:
            return []
        case .command(let arguments, let parse):
            guard let binary = resolveBinary(in: tool.binaries) else { return [] }
            let result = runCaptured(executable: binary, arguments: arguments, timeout: 15)
            return result.timedOut ? [] : CLIModelListParser.parse(result.stdout, format: parse)
        }
    }

    nonisolated private static func fallbackModels(_ tool: CLITool, configured: String?) -> [String] {
        var models: [String] = []
        if let configured, !configured.isEmpty {
            models.append(configured)
        }
        for alias in tool.documentedAliases where !models.contains(alias) {
            models.append(alias)
        }
        return models
    }

    nonisolated public static func detectionStatus(for preset: CLIPreset, customCommand: String = "") -> (isFound: Bool, details: String) {
        let status = readinessBlocking(for: preset, customCommand: customCommand, customAuthCommand: "")
        switch status.state {
        case .ready:
            return (true, status.version.map { "Ready (\($0))" } ?? "Ready")
        case .signInNeeded, .notInstalled:
            return (false, status.hint.isEmpty ? status.title : status.hint)
        case .unspecified:
            return (false, "")
        }
    }

    // MARK: - Invocation Building

    private struct ProcessInvocation: Sendable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let stdinText: String?
        let output: CLIOutputKind
    }

    nonisolated private static func cliEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // The same directory list the status check searched, so a launch and its children
        // see the binary that readiness reported.
        let discovered = CLIExecutableCache.shared.searchDirectories()
        let inherited = CLIExecutableSearch.parsePATH(env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["PATH"] = CLIExecutableSearch.searchDirectories(loginPATH: discovered, supplemental: inherited).joined(separator: ":")
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    /// Timeout-bounded: a stuck login shell or auth command counts as a failed check.
    nonisolated private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                ShellProcessRunner.terminateProcessGroup(process)
                return false
            }
            Thread.sleep(forTimeInterval: min(0.05, remaining))
        }
        return true
    }

    nonisolated public static func resolveBinaryPath(for binary: String) -> String? {
        CLIExecutableCache.shared.resolve(binary)
    }

    nonisolated static func invalidateExecutableCache() {
        CLIExecutableCache.shared.invalidate()
    }

    /// `$SHELL -l -c`, once per cache fill. Must not consult `cliEnvironment` — that calls back into the cache.
    nonisolated fileprivate static func captureLoginPATH() -> [String] {
        let shell = loginShellExecutable()
        let script = CLIExecutableSearch.loginPathScript(shellPath: shell)
        let result = runCaptured(
            executable: shell,
            arguments: ["-l", "-c", script],
            timeout: 8,
            environment: .inherit
        )
        let parsed = CLIExecutableSearch.pathFromLoginOutput(result.stdout)
        if parsed.isEmpty {
            Log.ai.debug("Login shell did not return a PATH; CLI lookup is using install locations")
        }
        return parsed
    }

    nonisolated private static func loginShellExecutable() -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["SHELL"],
            "/bin/zsh",
            "/bin/bash",
            "/bin/sh"
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("/"),
                  !trimmed.contains(where: \.isWhitespace),
                  FileManager.default.isExecutableFile(atPath: trimmed) else { continue }
            return trimmed
        }
        return "/bin/sh"
    }

    nonisolated fileprivate static func loadNvmLayout(at nvmDir: String) -> CLINvmLayout {
        let root = CLIExecutableSearch.trimmedDirectory(nvmDir)
        var aliases: [String: String] = [:]
        collectNvmAliases(in: root + "/alias", prefix: "", into: &aliases, depth: 0)
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: root + "/versions/node")) ?? []
        return CLINvmLayout(
            aliasFiles: aliases,
            versionNames: versions.filter { !$0.hasPrefix(".") }
        )
    }

    nonisolated private static func collectNvmAliases(in directory: String, prefix: String, into aliases: inout [String: String], depth: Int) {
        guard depth < 3, let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for name in names where !name.hasPrefix(".") {
            let path = directory + "/" + name
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            let key = prefix.isEmpty ? name : prefix + "/" + name
            if isDirectory.boolValue {
                collectNvmAliases(in: path, prefix: key, into: &aliases, depth: depth + 1)
            } else if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                aliases[key] = text
            }
        }
    }

    nonisolated private static func resolveBinary(in names: [String]) -> String? {
        for name in names {
            if let path = resolveBinaryPath(for: name) {
                return path
            }
        }
        return nil
    }

    nonisolated private static func buildInvocation(
        preset: CLIPreset,
        systemPrompt: String,
        userContent: String,
        customCommand: String,
        modelOverride: String
    ) throws -> ProcessInvocation {
        if preset == .custom {
            guard !customCommand.isEmpty else {
                throw AIError.providerUnavailable("Custom CLI command is empty. Configure it in Preferences → AI.")
            }
            var env = cliEnvironment()
            env["OPENCLIP_PROMPT"] = systemPrompt
            env["OPENCLIP_TEXT"] = userContent
            return ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-l", "-c", customCommand],
                environment: env,
                stdinText: userContent,
                output: .plainText
            )
        }

        guard let tool = CLITool.tool(for: preset) else {
            throw AIError.providerUnavailable("Unknown CLI preset.")
        }
        switch tool.runner {
        case .subprocess:
            break
        }
        guard let binary = resolveBinary(in: tool.binaries) else {
            throw AIError.providerUnavailable("\(tool.displayName) was not found. Install: \(tool.installCommand)")
        }
        let args = CLIArgumentPlan.arguments(
            template: tool.invocation,
            thinkingArguments: tool.thinkingArguments,
            systemPrompt: systemPrompt,
            userContent: userContent,
            model: modelOverride
        )
        let stdin: String? = tool.invocation.stdin == .userText ? userContent : nil
        return ProcessInvocation(
            executableURL: URL(fileURLWithPath: binary),
            arguments: args,
            environment: cliEnvironment(extra: tool.invocation.environment),
            stdinText: stdin,
            output: tool.invocation.output
        )
    }

    // MARK: - Process Execution

    private struct CommandCapture: Sendable {
        var exitCode: Int32
        var timedOut: Bool
        var stdout: String
        var stderr: String
    }

    private enum CapturedEnvironment {
        /// Login PATH plus install locations, shared with the status check.
        case cli
        /// Leave the environment alone. The login-shell PATH probe uses this so it cannot recurse into the cache.
        case inherit
    }

    nonisolated private static func runCaptured(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: CapturedEnvironment = .cli
    ) -> CommandCapture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if environment == .cli {
            process.environment = cliEnvironment()
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        let stdoutBuffer = DataBuffer(handle: stdoutPipe.fileHandleForReading)
        let stderrBuffer = DataBuffer(handle: stderrPipe.fileHandleForReading)
        stdoutBuffer.start()
        stderrBuffer.start()

        do {
            try process.run()
        } catch {
            return CommandCapture(exitCode: 1, timedOut: false, stdout: "", stderr: error.localizedDescription)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let exited = waitForExit(process, timeout: timeout)
        let stdout = String(data: stdoutBuffer.finish(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.finish(), encoding: .utf8) ?? ""
        if !exited {
            return CommandCapture(exitCode: 1, timedOut: true, stdout: stdout, stderr: stderr)
        }
        return CommandCapture(exitCode: process.terminationStatus, timedOut: false, stdout: stdout, stderr: stderr)
    }

    nonisolated private static func runStreamingProcess(
        invocation: ProcessInvocation,
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
            if let parsed = parseOutputLine(line, output: invocation.output), !parsed.isEmpty {
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
                let stdoutText = outAccumulator.capturedText()

                if process.terminationStatus != 0 {
                    let message = failureMessage(stderr: errStr, stdout: stdoutText, status: process.terminationStatus)
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

    nonisolated private static func failureMessage(stderr: String, stdout: String, status: Int32) -> String {
        let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = stderrTrimmed.isEmpty ? stdoutTrimmed : stderrTrimmed
        if raw.isEmpty {
            return "CLI process exited with code \(status)"
        }
        return raw.count > 500 ? String(raw.prefix(500)) : raw
    }

    nonisolated private static func parseOutputLine(_ line: String, output: CLIOutputKind) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch output {
        case .codexJSONL:
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
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

        case .plainText:
            return line + "\n"
        }
    }
}

// MARK: - Thread-safe Accumulators

private final class DataBuffer: @unchecked Sendable {
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

    func finish() -> Data {
        handle.readabilityHandler = nil
        let tail = handle.availableData
        lock.lock()
        data.append(tail)
        let result = data
        data.removeAll(keepingCapacity: false)
        lock.unlock()
        return result
    }
}

private final class LineStreamAccumulator: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var lineBuffer = ""
    private var captured = ""
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
            self.captured += chunk
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
        let tail = handle.availableData
        if let chunk = String(data: tail, encoding: .utf8), !chunk.isEmpty {
            lock.lock()
            lineBuffer += chunk
            captured += chunk
            lock.unlock()
        }
        lock.lock()
        let remaining = lineBuffer
        lineBuffer = ""
        lock.unlock()
        if !remaining.isEmpty {
            onLine(remaining)
        }
    }

    func capturedText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return captured
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
        let tail = handle.availableData
        lock.lock()
        data.append(tail)
        let result = data
        lock.unlock()
        return String(data: result, encoding: .utf8) ?? ""
    }
}

/// One login-shell PATH capture shared by status checks and launches.
/// A GUI app does not inherit the user's shell PATH, so lookup also checks Homebrew, npm, bun, Volta, and nvm.
private final class CLIExecutableCache: @unchecked Sendable {
    static let shared = CLIExecutableCache()

    private let stateLock = NSLock()
    private let loadLock = NSLock()
    private var generation = 0
    private var directories: [String]?
    private var capturedAt: Date?
    private var resolved: [String: String] = [:]
    private var logged: Set<String> = []
    /// Long enough that a status check and the launch that follows agree. Refresh drops it immediately.
    private let ttl: TimeInterval = 30

    func invalidate() {
        stateLock.lock()
        generation += 1
        directories = nil
        capturedAt = nil
        resolved.removeAll()
        logged.removeAll()
        stateLock.unlock()
    }

    func resolve(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let home = CLIExecutableSearch.trimmedDirectory(FileManager.default.homeDirectoryForCurrentUser.path)

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return CLIExecutableSearch.resolve(
                name: trimmed,
                home: home,
                directories: [],
                isExecutable: CLIExecutableSearch.isExecutableFile(at:)
            )
        }

        stateLock.lock()
        if let cached = resolved[trimmed], !isExpired {
            stateLock.unlock()
            return cached
        }
        let generationAtStart = generation
        stateLock.unlock()

        let directories = searchDirectories()
        let found = CLIExecutableSearch.resolve(
            name: trimmed,
            home: home,
            directories: directories,
            isExecutable: CLIExecutableSearch.isExecutableFile(at:)
        )

        stateLock.lock()
        var logHit: String?
        var logMiss = false
        if generation == generationAtStart {
            if let found {
                resolved[trimmed] = found
                if logged.insert(trimmed).inserted {
                    logHit = found
                }
            } else if logged.insert("missing:\(trimmed)").inserted {
                logMiss = true
            }
        }
        stateLock.unlock()

        if let logHit {
            Log.ai.debug("CLI \(trimmed, privacy: .public) resolved at \(logHit, privacy: .public)")
        } else if logMiss {
            Log.ai.debug("CLI \(trimmed, privacy: .public) was not found on the login PATH or in install locations")
        }
        return found
    }

    func searchDirectories() -> [String] {
        stateLock.lock()
        if let directories, !isExpired {
            stateLock.unlock()
            return directories
        }
        let generationAtStart = generation
        stateLock.unlock()

        loadLock.lock()
        defer { loadLock.unlock() }

        stateLock.lock()
        if let directories, !isExpired {
            stateLock.unlock()
            return directories
        }
        stateLock.unlock()

        let loaded = Self.probeDirectories()

        stateLock.lock()
        if generation == generationAtStart {
            directories = loaded
            capturedAt = Date()
            resolved.removeAll()
            logged.removeAll()
        }
        stateLock.unlock()
        return loaded
    }

    /// Caller holds `stateLock`.
    private var isExpired: Bool {
        guard let capturedAt else { return true }
        return Date().timeIntervalSince(capturedAt) >= ttl
    }

    private static func probeDirectories() -> [String] {
        let home = CLIExecutableSearch.trimmedDirectory(FileManager.default.homeDirectoryForCurrentUser.path)
        let loginPATH = CLIProvider.captureLoginPATH()
        let envNVM = ProcessInfo.processInfo.environment["NVM_DIR"].map { CLIExecutableSearch.trimmedDirectory($0) }
        let nvmDir: String
        if let envNVM, !envNVM.isEmpty {
            nvmDir = envNVM
        } else {
            nvmDir = home + "/.nvm"
        }
        let layout = CLIProvider.loadNvmLayout(at: nvmDir)
        let nvmBin = CLIExecutableSearch.nvmBinDirectory(home: home, nvmDir: nvmDir, layout: layout)
        let supplemental = CLIExecutableSearch.supplementalDirectories(home: home, nvmBin: nvmBin)
        let loaded = CLIExecutableSearch.searchDirectories(loginPATH: loginPATH, supplemental: supplemental)
        Log.ai.debug("CLI search path has \(loaded.count, privacy: .public) directories")
        return loaded
    }
}
