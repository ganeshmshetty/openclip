// LayaRuntime.swift
// OpenClip
//
// Runs Laya, the open-source System One decision model, on this Mac without any CLI. Laya ships
// only as a Python library, so OpenClip owns the runtime: a Python environment it creates under
// ~/.openclip/laya, the bundled `laya_bridge.py` kept resident as a child process, and JSON lines
// over stdin/stdout so a decision is one forward pass (tens of milliseconds on Apple silicon)
// rather than a model load. Install creates the environment (uv when available, else python3 -m
// venv), installs the `laya` package, then runs the bridge once with --warmup so the checkpoint
// (about 800 MB) lands in the same folder; Remove deletes that one directory.
import Foundation
import Core

@MainActor
public final class LayaRuntime: ObservableObject {
    public static let shared = LayaRuntime()

    public enum Status: Equatable, Sendable {
        case notInstalled
        case installing(step: String)
        case installed
        case starting(phase: String)
        case running(model: String, device: String)
        case failed(String)

        public var isBusy: Bool {
            switch self {
            case .installing, .starting: return true
            default: return false
            }
        }
    }

    public static let models: [(id: String, title: String)] = [
        ("english", String(localized: "English (421M, ModernBERT-large)")),
        ("multilingual", String(localized: "Multilingual (322M, 100+ languages)")),
    ]
    public static let defaultModel = "english"

    @Published public private(set) var status: Status
    /// Last line the installer or the bridge printed, shown under the status in Settings.
    @Published public private(set) var lastLogLine: String = ""

    public let directory: URL
    public var venvURL: URL { directory.appendingPathComponent("venv") }
    public var pythonURL: URL { venvURL.appendingPathComponent("bin/python") }
    public var cacheURL: URL { directory.appendingPathComponent("hf-cache") }
    public var logURL: URL { directory.appendingPathComponent("bridge.log") }

    /// Seconds without a decision before the resident model is unloaded (it holds well over 1 GB).
    public let idleTimeout: TimeInterval
    /// Longest wait for the bridge to report ready; a first start may still be downloading.
    public var startTimeout: TimeInterval = 30 * 60
    public var decideTimeout: TimeInterval = 120

    private var bridge: LayaBridgeProcess?
    private var idleTask: Task<Void, Never>?
    private var inFlight = 0

    public init(directory: URL = Constants.layaDirectory, idleTimeout: TimeInterval = 10 * 60) {
        self.directory = directory
        self.idleTimeout = idleTimeout
        let installed = FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("venv/bin/python").path)
        self.status = installed ? .installed : .notInstalled
    }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: pythonURL.path)
    }

    /// The bridge script bundled with the app (Sources/OpenClip/Resources/laya_bridge.py).
    public nonisolated static var bridgeScriptURL: URL? {
        Bundle(for: LayaRuntime.self).url(forResource: "laya_bridge", withExtension: "py")
    }

    // MARK: - Install / remove

    /// Creates the environment, installs `laya`, and warms the chosen model. Safe to call again
    /// after a failure: every step is idempotent.
    public func install(model: String) async {
        guard !status.isBusy else { return }
        guard let script = Self.bridgeScriptURL else {
            fail(String(localized: "The Laya bridge script is missing from this build."))
            return
        }
        stopBridge()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: logURL)
            appendLog("== install \(Date()) model=\(model)")

            step(String(localized: "Looking for uv or Python 3.10+…"))
            let toolchain = try await Toolchain.locate(runner: run)

            if !isInstalled {
                step(String(localized: "Creating the Python environment…"))
                switch toolchain {
                case .uv(let uv):
                    try await runOrThrow(uv, ["venv", "--python", "3.12", "--quiet", venvURL.path], step: "uv venv")
                case .python(let python):
                    try await runOrThrow(python, ["-m", "venv", venvURL.path], step: "python -m venv")
                }
            }

            step(String(localized: "Installing Laya, PyTorch and Transformers…"))
            switch toolchain {
            case .uv(let uv):
                try await runOrThrow(uv, ["pip", "install", "--python", pythonURL.path, "--quiet", "laya"], step: "uv pip install")
            case .python:
                try await runOrThrow(pythonURL, ["-m", "pip", "install", "--quiet", "--upgrade", "pip", "laya"], step: "pip install")
            }

            try await warm(model: model, script: script)
            status = .installed
            lastLogLine = String(localized: "Laya is ready.")
            Log.decisions.info("Laya runtime installed (model \(model, privacy: .public))")
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Downloads and loads `model` once so the first decision does not pay for it. Used after the
    /// user switches models in Settings.
    public func prepare(model: String) async {
        guard isInstalled, !status.isBusy, let script = Self.bridgeScriptURL else { return }
        stopBridge()
        do {
            try await warm(model: model, script: script)
            status = .installed
            lastLogLine = String(localized: "Model ready.")
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Stops the bridge and deletes the environment, cache and log.
    public func uninstall() {
        stopBridge()
        try? FileManager.default.removeItem(at: directory)
        status = .notInstalled
        lastLogLine = ""
        Log.decisions.info("Laya runtime removed")
    }

    private func warm(model: String, script: URL) async throws {
        step(String(localized: "Preparing the model (first run downloads about 800 MB)…"))
        let fatal = SendableBox<String?>(nil)
        let code = try await run(pythonURL, [script.path, "--warmup", "--model", model], environment: bridgeEnvironment(), onStdout: { [weak self] line in
            guard case .event(let name, let fields)? = LayaBridgeEnvelope.parse(line) else { return }
            let text: String?
            switch name {
            case "status": text = Self.describe(phase: fields[string: "phase"] ?? name)
            case "ready": text = String(localized: "Model loaded, running a first decision…")
            case "fatal": fatal.value = fields[string: "error"]; text = nil
            default: text = nil
            }
            guard let text else { return }
            Task { @MainActor [weak self] in self?.step(text) }
        })
        if code != 0 {
            throw LayaRuntimeError.stepFailed(step: "warmup", detail: fatal.value ?? lastStderrLines())
        }
    }

    // MARK: - Decisions

    /// Sends one request through the resident bridge, starting it (and switching model) as needed.
    /// `payload` is `DecisionQuestionPacker.encodeRequest` output; the reply is what
    /// `DecisionResponseParser.parse` reads.
    public func decide(_ payload: Data, model: String) async throws -> Data {
        guard isInstalled else {
            throw DecisionError.providerUnavailable(Self.notInstalledMessage)
        }
        if case .installing(let step) = status {
            throw DecisionError.providerUnavailable(String(localized: "Laya is still installing: \(step)"))
        }
        let bridge = try await bridge(for: model)
        inFlight += 1
        defer {
            inFlight -= 1
            scheduleIdleStop()
        }
        do {
            return try await bridge.send(payload, timeout: decideTimeout)
        } catch let error as LayaRuntimeError {
            if case .bridgeExited = error { stopBridge() }
            throw DecisionError.providerUnavailable(error.localizedDescription)
        }
    }

    /// Unloads the model now (Settings "Unload", idle timeout, model switch, remove).
    public func stopBridge() {
        idleTask?.cancel()
        idleTask = nil
        bridge?.shutdown()
        bridge = nil
        if case .running = status { status = .installed }
        if case .starting = status { status = .installed }
    }

    private func bridge(for model: String) async throws -> LayaBridgeProcess {
        if let bridge, bridge.isRunning, bridge.model == model {
            return bridge
        }
        stopBridge()
        guard let script = Self.bridgeScriptURL else {
            throw DecisionError.providerUnavailable(String(localized: "The Laya bridge script is missing from this build."))
        }
        let process = LayaBridgeProcess(
            python: pythonURL,
            script: script,
            model: model,
            environment: bridgeEnvironment(),
            logURL: logURL
        )
        process.onPhase = { [weak self] phase in
            Task { @MainActor [weak self] in
                guard let self, self.bridge === process else { return }
                self.status = .starting(phase: Self.describe(phase: phase))
            }
        }
        process.onExit = { [weak self] code in
            Task { @MainActor [weak self] in
                guard let self, self.bridge === process else { return }
                self.bridge = nil
                if code != 0 {
                    let detail = self.lastStderrLines()
                    self.status = .failed(String(localized: "Laya stopped unexpectedly (exit \(code)). \(detail)"))
                    Log.decisions.error("Laya bridge exited with \(code, privacy: .public)")
                } else {
                    self.status = .installed
                }
            }
        }
        bridge = process
        status = .starting(phase: String(localized: "Starting…"))
        do {
            try process.start()
            let ready = try await process.waitUntilReady(timeout: startTimeout)
            status = .running(model: ready.model, device: ready.device)
            lastLogLine = String(localized: "Loaded \(ready.model) on \(ready.device) in \(ready.loadMS / 1000) s.")
            Log.decisions.info("Laya bridge ready: \(ready.model, privacy: .public) on \(ready.device, privacy: .public)")
            return process
        } catch {
            process.shutdown()
            if bridge === process { bridge = nil }
            let message = (error as? LayaRuntimeError)?.localizedDescription ?? error.localizedDescription
            status = .failed(message)
            throw DecisionError.providerUnavailable(message)
        }
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        guard inFlight == 0, idleTimeout > 0 else { return }
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.idleTimeout ?? 0) * 1_000_000_000)
            guard let self, !Task.isCancelled, self.inFlight == 0 else { return }
            Log.decisions.info("Laya bridge idle; unloading")
            self.stopBridge()
        }
    }

    // MARK: - Helpers

    public nonisolated static var notInstalledMessage: String {
        String(localized: "Laya is not installed. Open Settings → Decisions and choose Install Laya.")
    }

    nonisolated static func describe(phase: String) -> String {
        switch phase {
        case "importing": return String(localized: "Loading PyTorch…")
        case "downloading": return String(localized: "Downloading the model (about 800 MB)…")
        case "loading": return String(localized: "Loading the model…")
        default: return phase
        }
    }

    private func bridgeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HF_HOME"] = cacheURL.path
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONNOUSERSITE"] = "1"
        env.removeValue(forKey: "PYTHONHOME")
        env.removeValue(forKey: "PYTHONPATH")
        env["PATH"] = Toolchain.searchPATH(base: env["PATH"])
        return env
    }

    private func step(_ text: String) {
        status = .installing(step: text)
        lastLogLine = text
        appendLog("-- \(text)")
    }

    private func fail(_ message: String) {
        status = .failed(message)
        lastLogLine = message
        appendLog("!! \(message)")
        Log.decisions.error("Laya runtime: \(message, privacy: .public)")
    }

    private func runOrThrow(_ executable: URL, _ arguments: [String], step name: String) async throws {
        let code = try await run(executable, arguments, environment: bridgeEnvironment())
        if code != 0 {
            throw LayaRuntimeError.stepFailed(step: name, detail: lastStderrLines())
        }
    }

    private var recentStderr: [String] = []

    /// Runs a one-shot process, streaming its output to the log (and `lastLogLine`).
    private func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        onStdout: (@Sendable (String) -> Void)? = nil
    ) async throws -> Int32 {
        appendLog("$ \(executable.path) \(arguments.joined(separator: " "))")
        let stdoutHandler: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.appendLog(line)
                if onStdout == nil { self?.lastLogLine = line }
            }
            onStdout?(line)
        }
        let stderrHandler: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendLog(line)
                self.recentStderr.append(line)
                if self.recentStderr.count > 6 { self.recentStderr.removeFirst() }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !trimmed.hasPrefix("\u{1B}") { self.lastLogLine = trimmed }
            }
        }
        recentStderr = []
        return try await StreamingProcess.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: startTimeout,
            onStdout: stdoutHandler,
            onStderr: stderrHandler
        )
    }

    private func lastStderrLines() -> String {
        let lines = recentStderr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !lines.isEmpty { return lines.suffix(2).joined(separator: " ") }
        // The bridge's stderr goes straight to the log file; surface its tail instead.
        if let text = try? String(contentsOf: logURL, encoding: .utf8) {
            let tail = text.split(separator: "\n").suffix(2).map(String.init)
            if !tail.isEmpty { return tail.joined(separator: " ") }
        }
        return String(localized: "See \(logURL.path).")
    }

    private func appendLog(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}

public enum LayaRuntimeError: Error, LocalizedError, Equatable {
    case toolchainMissing
    case stepFailed(step: String, detail: String)
    case bridgeExited(code: Int32, detail: String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .toolchainMissing:
            return String(localized: "Laya needs uv or Python 3.10 or newer. Install uv (https://docs.astral.sh/uv) or Python (brew install python) and try again.")
        case .stepFailed(let step, let detail):
            return String(localized: "Laya install failed at \(step): \(detail)")
        case .bridgeExited(let code, let detail):
            return String(localized: "Laya stopped (exit \(code)). \(detail)")
        case .timeout(let what):
            return String(localized: "Laya timed out while \(what).")
        }
    }
}

// MARK: - Toolchain discovery

enum Toolchain {
    case uv(URL)
    case python(URL)

    /// Directories where uv and Homebrew or python.org Pythons live; a GUI app's PATH is minimal.
    static let extraPaths = [
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.cargo/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/Library/Frameworks/Python.framework/Versions/Current/bin",
    ]

    static func searchPATH(base: String?) -> String {
        let current = (base ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (extraPaths + current + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }

    @MainActor
    static func locate(
        runner: (URL, [String], [String: String], (@Sendable (String) -> Void)?) async throws -> Int32
    ) async throws -> Toolchain {
        let fm = FileManager.default
        let dirs = searchPATH(base: ProcessInfo.processInfo.environment["PATH"]).split(separator: ":").map(String.init)
        for dir in dirs {
            let uv = URL(fileURLWithPath: dir).appendingPathComponent("uv")
            if fm.isExecutableFile(atPath: uv.path) { return .uv(uv) }
        }
        // No uv: accept the first python3 that is 3.10 or newer (torch has wheels through 3.14).
        var candidates: [URL] = []
        for dir in dirs {
            for name in ["python3.13", "python3.12", "python3.11", "python3.10", "python3"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: url.path), !candidates.contains(url) { candidates.append(url) }
            }
        }
        for python in candidates {
            let version = SendableBox("")
            let code = try? await runner(python, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"], ProcessInfo.processInfo.environment) { line in
                version.value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard code == 0, let parsed = parse(version: version.value), parsed.0 == 3, parsed.1 >= 10 else { continue }
            return .python(python)
        }
        throw LayaRuntimeError.toolchainMissing
    }

    static func parse(version: String) -> (Int, Int)? {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}

// MARK: - Bridge protocol

/// One line from the bridge: an unsolicited event, or the reply to a request id.
public enum LayaBridgeEnvelope: Equatable {
    case event(name: String, fields: [String: AnyHashableJSON])
    case reply(id: Int, response: Data?, error: String?)

    public static func parse(_ line: String) -> LayaBridgeEnvelope? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let name = object["event"] as? String {
            var fields: [String: AnyHashableJSON] = [:]
            for (key, value) in object where key != "event" {
                fields[key] = AnyHashableJSON(value)
            }
            return .event(name: name, fields: fields)
        }
        if let id = object["id"] as? Int {
            if let response = object["response"], JSONSerialization.isValidJSONObject(response),
               let data = try? JSONSerialization.data(withJSONObject: response) {
                return .reply(id: id, response: data, error: nil)
            }
            return .reply(id: id, response: nil, error: object["error"] as? String ?? "malformed reply")
        }
        return nil
    }
}

/// Minimal hashable wrapper so envelope events stay `Equatable` for tests.
public struct AnyHashableJSON: Equatable, Hashable, CustomStringConvertible {
    public let value: AnyHashable?
    public init(_ raw: Any) { self.value = raw as? AnyHashable }
    public var description: String { value.map { String(describing: $0) } ?? "null" }
}

extension Dictionary where Key == String, Value == AnyHashableJSON {
    subscript(string key: String) -> String? { self[key]?.value as? String }
    subscript(int key: String) -> Int? { self[key]?.value as? Int }
}

/// Lock-guarded box for values a @Sendable callback fills in.
final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// The resident `laya_bridge.py` child: launches it, matches replies to request ids, and reports
/// phase events while the model loads.
final class LayaBridgeProcess: @unchecked Sendable {
    let model: String
    var onPhase: (@Sendable (String) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var ready: CheckedContinuation<(model: String, device: String, loadMS: Int), Error>?
    private var exited = false
    private var exitCode: Int32 = 0

    init(python: URL, script: URL, model: String, environment: [String: String], logURL: URL) {
        self.model = model
        process.executableURL = python
        process.arguments = [script.path, "--model", model]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            _ = try? log.seekToEnd()
            process.standardError = log
        }
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !exited && process.isRunning
    }

    func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.consume(chunk)
        }
        process.terminationHandler = { [weak self] proc in
            self?.handleExit(code: proc.terminationStatus)
        }
        try process.run()
    }

    func waitUntilReady(timeout: TimeInterval) async throws -> (model: String, device: String, loadMS: Int) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if exited {
                lock.unlock()
                continuation.resume(throwing: LayaRuntimeError.bridgeExited(code: exitCode, detail: ""))
                return
            }
            ready = continuation
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.failReady(with: LayaRuntimeError.timeout("loading the model"))
            }
        }
    }

    func send(_ payload: Data, timeout: TimeInterval) async throws -> Data {
        guard let request = try? JSONSerialization.jsonObject(with: payload) else {
            throw LayaRuntimeError.stepFailed(step: "encode", detail: "request is not JSON")
        }
        let id = allocateRequestID()
        let envelope: [String: Any] = ["op": "decide", "id": id, "request": request]
        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(0x0A)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if exited {
                lock.unlock()
                continuation.resume(throwing: LayaRuntimeError.bridgeExited(code: exitCode, detail: ""))
                return
            }
            pending[id] = continuation
            lock.unlock()
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: line)
            } catch {
                resume(id: id, with: .failure(LayaRuntimeError.bridgeExited(code: exitCode, detail: error.localizedDescription)))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resume(id: id, with: .failure(LayaRuntimeError.timeout("waiting for a decision")))
            }
        }
    }

    func shutdown() {
        lock.lock()
        let alreadyExited = exited
        lock.unlock()
        guard !alreadyExited else { return }
        if let data = "{\"op\":\"shutdown\"}\n".data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdinPipe.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning {
                ShellProcessRunner.terminateProcessGroup(process, fallbackDelay: 0.5)
            }
        }
    }

    // MARK: Plumbing

    /// Synchronous on purpose: NSLock may not be taken from an async context in Swift 6.
    private func allocateRequestID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        return id
    }

    private func consume(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        lock.unlock()
        for line in lines {
            handle(line: line)
        }
    }

    private func handle(line: String) {
        guard let envelope = LayaBridgeEnvelope.parse(line) else { return }
        switch envelope {
        case .event(let name, let fields):
            switch name {
            case "status":
                onPhase?(fields[string: "phase"] ?? name)
            case "ready":
                lock.lock()
                let continuation = ready
                ready = nil
                lock.unlock()
                continuation?.resume(returning: (
                    model: fields[string: "model"] ?? model,
                    device: fields[string: "device"] ?? "?",
                    loadMS: fields[int: "load_ms"] ?? 0
                ))
            case "fatal":
                failReady(with: LayaRuntimeError.stepFailed(step: "load", detail: fields[string: "error"] ?? "unknown error"))
            default:
                break
            }
        case .reply(let id, let response, let error):
            if let response {
                resume(id: id, with: .success(response))
            } else {
                resume(id: id, with: .failure(DecisionError.providerUnavailable(error ?? "Laya returned an error")))
            }
        }
    }

    private func resume(id: Int, with result: Result<Data, Error>) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func failReady(with error: Error) {
        lock.lock()
        let continuation = ready
        ready = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func handleExit(code: Int32) {
        lock.lock()
        exited = true
        exitCode = code
        let waiting = pending
        pending = [:]
        let readyWaiter = ready
        ready = nil
        lock.unlock()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        let error = LayaRuntimeError.bridgeExited(code: code, detail: "")
        readyWaiter?.resume(throwing: error)
        for (_, continuation) in waiting {
            continuation.resume(throwing: error)
        }
        onExit?(code)
    }
}

// MARK: - One-shot streaming process

/// Runs a process to completion, delivering stdout and stderr line by line as they arrive, with a
/// watchdog that kills the process group on timeout. Used for the install steps.
enum StreamingProcess {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let box = SendableBox(Process())
        let process = box.value
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let outSplitter = LineSplitter(onLine: onStdout)
        let errSplitter = LineSplitter(onLine: onStderr)
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; outSplitter.finish() } else { outSplitter.feed(chunk) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; errSplitter.finish() } else { errSplitter.feed(chunk) }
        }
        let timedOut = AtomicFlag()
        return try await withCheckedThrowingContinuation { continuation in
            let finished = AtomicFlag()
            process.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                outSplitter.finish()
                errSplitter.finish()
                guard !finished.isSet else { return }
                finished.set()
                if timedOut.isSet {
                    continuation.resume(throwing: LayaRuntimeError.timeout("running \(executable.lastPathComponent)"))
                } else {
                    continuation.resume(returning: proc.terminationStatus)
                }
            }
            do {
                try process.run()
            } catch {
                guard !finished.isSet else { return }
                finished.set()
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                let running = box.value
                guard running.isRunning else { return }
                timedOut.set()
                ShellProcessRunner.terminateProcessGroup(running, fallbackDelay: 0.5)
            }
        }
    }

    private final class LineSplitter: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let onLine: @Sendable (String) -> Void

        init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

        func feed(_ chunk: Data) {
            lock.lock()
            buffer.append(chunk)
            var lines: [String] = []
            // pip and uv redraw progress with carriage returns; treat them as line breaks.
            while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let lineData = buffer.subdata(in: buffer.startIndex..<index)
                buffer.removeSubrange(buffer.startIndex...index)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
            }
            lock.unlock()
            lines.forEach(onLine)
        }

        func finish() {
            lock.lock()
            let rest = buffer
            buffer = Data()
            lock.unlock()
            if let line = String(data: rest, encoding: .utf8), !line.isEmpty { onLine(line) }
        }
    }
}
