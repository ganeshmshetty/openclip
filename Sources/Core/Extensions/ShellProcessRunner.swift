// ShellProcessRunner.swift
// OpenClip
//
// Shared Core subprocess executor for one-shot shell runtimes (ScriptAction script files and
// CustomAction.shellScript inline commands). Converges the two former watchdog implementations onto
// ONE mechanism (Gotcha 8): a GCD timer marks a `TimeoutFlag`, terminates the process (hard-killing
// it a moment later if it ignores the signal), and a timeout always surfaces as an error. Pipe
// output is read through GCD readability handlers — never a blocking readToEnd() — so a stuck
// child can't wedge a Swift cooperative thread, and stdin is seeded and closed synchronously so a
// script reading stdin always sees EOF. Non-zero exits throw with the stderr text, unifying the
// error policy across both shell runtimes (Gotcha 5).
//
// Also hosts the relocated `TimeoutFlag` (was `internal` in CustomAction.swift) and `OnceGate`
// (was `private`; now `internal` and retained for future async JS host callbacks — plan §8), the
// expanded `ScriptJSONOutput` DTO, and the shared JSON→ActionResult mapper. Pure Foundation — no
// AppKit/SwiftUI.
import Foundation

/// Thread-safe boolean flag guarded by an NSLock.
public final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init(initialValue: Bool = false) {
        self.flag = initialValue
    }

    public func set() {
        lock.lock()
        defer { lock.unlock() }
        flag = true
    }

    public var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    public func markTimedOut() { set() }
    public var isTimedOut: Bool { isSet }
    public func markCancelled() { set() }
    public var isCancelled: Bool { isSet }
}

public typealias TimeoutFlag = AtomicFlag
public typealias CancellationFlag = AtomicFlag

/// Thread-safe container to hold a running Process so that Task cancellation handlers
/// can immediately terminate the process and its subprocess group.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldKill = cancelled && process.isRunning
        lock.unlock()
        if shouldKill {
            terminate(process)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning {
            terminate(proc)
        }
    }

    private func terminate(_ process: Process) {
        ShellProcessRunner.terminateProcessGroup(process, fallbackDelay: 0.5)
    }
}

/// Accumulates a subprocess pipe's output through a GCD readability handler so no thread ever
/// blocks on a pipe that a misbehaving child (or a grandchild that inherited the fd) refuses to
/// close. `readabilityHandler` is dispatch-source backed, so it runs regardless of how loaded the
/// Swift concurrency executor is, and the caller is never left holding a wedged reader.
private final class PipeAccumulator: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private let eofGroup = DispatchGroup()
    private var isFinished = false

    init(fileHandle: FileHandle) {
        self.handle = fileHandle
    }

    func start() {
        eofGroup.enter()
        handle.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.isFinished else { return }
            let chunk = fh.availableData
            if chunk.isEmpty {
                self.isFinished = true
                self.handle.readabilityHandler = nil
                self.eofGroup.leave()
            } else {
                self.buffer.append(chunk)
            }
        }
    }

    /// Drains pending output and closes the handle. Bounded: waits at most `grace` seconds for EOF
    /// so a grandchild still holding the pipe can't block the caller indefinitely.
    func finish(grace: TimeInterval = 2.0) {
        _ = eofGroup.wait(timeout: .now() + grace)
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else {
            try? handle.close()
            return
        }
        isFinished = true
        handle.readabilityHandler = nil
        eofGroup.leave()

        let fd = handle.fileDescriptor
        if fd >= 0 {
            let flags = fcntl(fd, F_GETFL)
            if flags >= 0 {
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            }

            var chunkBuf = [UInt8](repeating: 0, count: 16384)
            var drainIterations = 0
            let maxDrainIterations = 256
            while drainIterations < maxDrainIterations {
                let bytesRead = read(fd, &chunkBuf, chunkBuf.count)
                if bytesRead > 0 {
                    buffer.append(contentsOf: chunkBuf[0..<bytesRead])
                    drainIterations += 1
                } else if bytesRead < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
        try? handle.close()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Reference box so the value-type `ScriptJSONOutput` can recursively contain itself via `effect`
/// (a Swift struct cannot have a stored property that recursively contains it).
final class ScriptJSONEffect: Decodable {
    let value: ScriptJSONOutput
    init(from decoder: Decoder) throws {
        self.value = try ScriptJSONOutput(from: decoder)
    }
}

/// Expanded shell stdout JSON protocol (plan Phase 6 Types). All fields except `type` are optional.
struct ScriptJSONOutput: Decodable {
    let type: String
    let value: String?
    let message: String?
    let style: String?
    let missing: [String]?
    let reason: String?
    let effect: ScriptJSONEffect?
    let key: String?
    let modifiers: [String]?
    let name: String?
    let shortcutName: String?
    let input: String?
    let title: String?
    let body: String?
    let actions: [ScriptJSONEffect]?
    let identifier: String?
    let keepVisible: Bool?
    let html: String?
    let rtf: String?
}

/// Maps shell stdout JSON into an `ActionResult` (plan §6 protocol). Returns nil when the output
/// does not decode as a `ScriptJSONOutput`, so callers fall through to plain-text handling; a
/// decoded but unknown `type` maps to `.success` (the current default path).
enum ShellResultMapper {
    static func actionResult(from stdout: String, actionID: String) -> ActionResult? {
        guard let data = stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScriptJSONOutput.self, from: data) else {
            return nil
        }
        return map(decoded, actionID: actionID)
    }

    private static func mapModifiers(_ rawModifiers: [String]?) -> [KeyPressSpec.KeyModifier] {
        guard let rawModifiers else { return [] }
        return rawModifiers.compactMap { element in
            switch element.lowercased() {
            case "command", "cmd": return .command
            case "shift": return .shift
            case "option", "alt": return .option
            case "control", "ctrl": return .control
            default: return nil
            }
        }
    }

    private static func map(_ output: ScriptJSONOutput, actionID: String) -> ActionResult {
        switch output.type {
        case Constants.actionTypePaste:
            guard let value = output.value else { return .success }
            return .paste(value)
        case Constants.actionTypeCopy:
            guard let value = output.value else { return .success }
            return .copy(value)
        case Constants.actionTypePasteContent, "paste-content":
            let payload = RichPasteboardPayload(plainText: output.value, rtf: output.rtf, html: output.html)
            return .pasteContent(payload)
        case Constants.actionTypeCopyContent, "copy-content":
            let payload = RichPasteboardPayload(plainText: output.value, rtf: output.rtf, html: output.html)
            return .copyContent(payload)
        case "cut":
            return .cut(output.value ?? "")
        case Constants.actionTypeOpenURL, "url":
            guard let value = output.value, let url = URL(string: value) else { return .success }
            return .openURL(url)
        case "keyPress", "keypress":
            guard let key = output.key, !key.isEmpty else { return .success }
            let modifiers = mapModifiers(output.modifiers)
            return .keyPress(KeyPressSpec(key: key, modifiers: modifiers))
        case "runShortcut", "shortcut":
            guard let name = output.name ?? output.shortcutName, !name.isEmpty else { return .success }
            return .runShortcut(name: name, input: output.input ?? output.value)
        case "notify", "notification":
            let title = output.title ?? output.message ?? "OpenClip"
            let body = output.body ?? (output.title != nil ? output.message ?? "" : "")
            return .notify(title: title, body: body)
        case "shareService", "share":
            guard let identifier = output.identifier, !identifier.isEmpty else {
                return .failure(NSError(
                    domain: Constants.actionErrorDomain,
                    code: Int(Constants.actionErrorCode),
                    userInfo: [NSLocalizedDescriptionKey: "shareService requires a non-empty identifier"]
                ))
            }
            return .shareService(identifier: identifier, text: output.value ?? output.input ?? "")
        case "sequence":
            guard let actions = output.actions, !actions.isEmpty else { return .success }
            let mappedResults = actions.map { map($0.value, actionID: actionID) }
            return .sequence(mappedResults)
        case "fail", "failure", "error":
            let msg = output.message ?? output.reason ?? output.value ?? "Script reported failure"
            let err = NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
            return .failure(err)
        case "toast":
            let style: StatusFeedback.Style
            switch output.style?.lowercased() {
            case "success": style = .success
            case "error": style = .error
            default: style = .info
            }
            return .toast(StatusFeedback(message: output.message ?? "", style: style, keepVisible: output.keepVisible ?? false))
        case "configure":
            return .openConfiguration(ConfigurationRequest(
                actionID: actionID,
                reason: output.reason,
                missingOptionIDs: output.missing ?? []
            ))
        default:
            return .success
        }
    }
}

/// Runs a subprocess to completion (or to the watchdog timeout) and returns its captured output.
/// Throws on non-zero exit (stderr text as the message) and on timeout — the unified stricter
/// error policy both shell runtimes adopt.
public enum ShellProcessRunner {
    public struct Invocation: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        /// Text written to the subprocess's stdin (then the pipe is closed). nil leaves stdin unseeded.
        public var stdinText: String?
        /// Runtime budget before the watchdog kills the subprocess. Defaults to
        /// `Constants.scriptTimeout` (60 s); tests override with a short value.
        public var timeout: TimeInterval?

        public init(
            executableURL: URL,
            arguments: [String],
            environment: [String: String] = [:],
            stdinText: String? = nil,
            timeout: TimeInterval? = nil
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.stdinText = stdinText
            self.timeout = timeout
        }
    }

    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let terminationStatus: Int32
    }

    public static func terminateProcessGroup(_ process: Process, fallbackDelay: TimeInterval = 0.5) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        process.terminate()
        if getpgid(pid) == pid {
            kill(-pid, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + fallbackDelay) {
            if process.isRunning {
                process.terminate()
                if getpgid(pid) == pid {
                    kill(-pid, SIGKILL)
                } else {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    public static func run(_ invocation: Invocation) async throws -> Output {
        try Task.checkCancellation()

        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await Task.detached {
                if processBox.isCancelled {
                    throw CancellationError()
                }

                let process = Process()
                process.executableURL = invocation.executableURL
                process.arguments = invocation.arguments
                process.environment = invocation.environment

                let stdOutPipe = Pipe()
                process.standardOutput = stdOutPipe
                let stdErrPipe = Pipe()
                process.standardError = stdErrPipe
                let stdInPipe = Pipe()
                process.standardInput = stdInPipe

                // GCD-backed pipe readers: they never block a Swift cooperative thread, so a slow or
                // stuck child can't wedge the concurrency pool the way blocking readToEnd() calls could.
                let outReader = PipeAccumulator(fileHandle: stdOutPipe.fileHandleForReading)
                let errReader = PipeAccumulator(fileHandle: stdErrPipe.fileHandleForReading)
                outReader.start()
                errReader.start()

                var watchdog: DispatchSourceTimer?
                defer {
                    watchdog?.cancel()
                    outReader.finish()
                    errReader.finish()
                }

                try process.run()

                // Move the child into its own process group so a watchdog kill can signal the whole tree
                // (the script plus any grandchildren it spawned) rather than only the direct child. The
                // child's pid becomes the group id; a failed setpgid is tolerated — the group signal just
                // no-ops below.
                setpgid(process.processIdentifier, process.processIdentifier)
                processBox.set(process)

                if processBox.isCancelled {
                    process.waitUntilExit()
                    throw CancellationError()
                }

                // Watchdog on a GCD timer — independent of the Swift concurrency executor, so it always
                // fires even if the cooperative pool is starved. Past the budget it terminates the
                // process and hard-kills it shortly after if the signal was ignored, then releases the
                // pipes. A watchdog kill surfaces as a timeout error. Armed before the stdin write below
                // so an oversized write that blocks the child not reading still gets killed on budget.
                let timeoutFlag = TimeoutFlag()
                let budget = invocation.timeout ?? Constants.scriptTimeout
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + budget, leeway: .milliseconds(50))
                timer.setEventHandler { [weak process] in
                    timeoutFlag.markTimedOut()
                    guard let process, process.isRunning else { return }
                    terminateProcessGroup(process, fallbackDelay: 0.5)
                }
                timer.resume()
                watchdog = timer

                // Seed stdin synchronously and close the write end, so a child script that reads stdin
                // always sees EOF — it can never block forever waiting for input.
                if let textData = invocation.stdinText?.data(using: .utf8) {
                    try? stdInPipe.fileHandleForWriting.write(contentsOf: textData)
                }
                try? stdInPipe.fileHandleForWriting.close()

                process.waitUntilExit()

                if processBox.isCancelled {
                    throw CancellationError()
                }

                if timeoutFlag.isTimedOut {
                    throw NSError(domain: Constants.actionErrorDomain,
                                  code: Int(Constants.actionErrorCode) + 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(budget)) seconds"])
                }

                let outData = outReader.data
                let errData = errReader.data

                if process.terminationStatus != 0 {
                    let errText = String(data: errData, encoding: .utf8) ?? ""
                    let errMsg = errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Script exited with code \(process.terminationStatus)"
                        : errText
                    throw NSError(domain: Constants.actionErrorDomain,
                                  code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: errMsg])
                }

                return Output(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    terminationStatus: process.terminationStatus
                )
            }.value
        } onCancel: {
            processBox.cancel()
        }
    }
}
