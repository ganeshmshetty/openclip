// ShellProcessRunner.swift
// OpenClip
//
// Shared Core subprocess executor for one-shot shell runtimes (ScriptAction script files and
// CustomAction.shellScript inline commands). Converges the two former watchdog implementations onto
// ONE mechanism (Gotcha 8): a `Task.detached` sleep that marks a `TimeoutFlag`, closes the
// stdout/stderr read ends (SIGPIPE to the process and any backgrounded children), terminates the
// process, then `waitUntilExit()`; a timeout always surfaces as an error. Non-zero exits throw with
// the stderr text, unifying the error policy across both shell runtimes (Gotcha 5).
//
// Also hosts the relocated `TimeoutFlag` (was `internal` in CustomAction.swift) and `OnceGate`
// (was `private`; now `internal` and retained for future async JS host callbacks — plan §8), the
// expanded `ScriptJSONOutput` DTO, and the shared JSON→ActionResult mapper. Pure Foundation — no
// AppKit/SwiftUI.
import Foundation

/// Thread-safe flag set by a subprocess watchdog when the execution budget is exceeded.
final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        timedOut = true
    }

    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
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

/// Expanded shell stdout JSON protocol (plan Phase 6 Types). All fields except `type` are
/// optional; `effect` is recursive for the keepVisible wrapper.
struct ScriptJSONOutput: Decodable {
    let type: String
    let value: String?
    let title: String?
    let body: String?
    let message: String?
    let style: String?
    let missing: [String]?
    let reason: String?
    let effect: ScriptJSONEffect?
    let footer: [String]?
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

    private static func map(_ output: ScriptJSONOutput, actionID: String) -> ActionResult {
        switch output.type {
        case Constants.actionTypePaste:
            guard let value = output.value else { return .success }
            return .paste(value)
        case Constants.actionTypeCopy:
            guard let value = output.value else { return .success }
            return .copy(value)
        case Constants.actionTypeOpenURL:
            guard let value = output.value, let url = URL(string: value) else { return .success }
            return .openURL(url)
        case "showContent":
            let body = output.body ?? ""
            var footer: [ContentOption] = []
            for preset in output.footer ?? [] {
                switch preset.lowercased() {
                case "paste":
                    footer.append(ContentOption(title: "Paste", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste(body))))
                case "copy":
                    footer.append(ContentOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy(body))))
                default:
                    break
                }
            }
            return .showContent(PopupContent(
                title: output.title,
                rows: body.isEmpty ? [] : [.text(body)],
                footer: footer,
                emphasis: .result
            ))
        case "status":
            let style: StatusFeedback.Style
            switch output.style?.lowercased() {
            case "success": style = .success
            case "error": style = .error
            default: style = .info
            }
            return .showStatus(StatusFeedback(message: output.message ?? "", style: style))
        case "keepVisible":
            guard let effect = output.effect?.value else { return .success }
            return .keepVisible(map(effect, actionID: actionID))
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

        public init(
            executableURL: URL,
            arguments: [String],
            environment: [String: String] = [:],
            stdinText: String? = nil
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.stdinText = stdinText
        }
    }

    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let terminationStatus: Int32
    }

    public static func run(_ invocation: Invocation) async throws -> Output {
        try await Task.detached {
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

            try process.run()

            // Watchdog: kill the process if it exceeds the runtime budget so the popup never spins
            // forever. Closing the stdout/stderr read ends sends SIGPIPE to every writer (the
            // process and any backgrounded children that retained a pipe), unblocking the readers
            // below even when a child outlives the shell. A watchdog kill is surfaced as a timeout
            // error.
            let timeoutFlag = TimeoutFlag()
            let timeoutTask = Task.detached { [weak process] in
                try? await Task.sleep(nanoseconds: UInt64(Constants.scriptTimeout * 1_000_000_000))
                timeoutFlag.markTimedOut()
                try? stdOutPipe.fileHandleForReading.close()
                try? stdErrPipe.fileHandleForReading.close()
                if process?.isRunning == true {
                    process?.terminate()
                }
            }
            defer { timeoutTask.cancel() }

            let writeTask = Task.detached {
                defer { try? stdInPipe.fileHandleForWriting.close() }
                if let textData = invocation.stdinText?.data(using: .utf8) {
                    do {
                        try stdInPipe.fileHandleForWriting.write(contentsOf: textData)
                    } catch {
                        let nsErr = error as NSError
                        if nsErr.domain == NSPOSIXErrorDomain && nsErr.code == Int(EPIPE) {
                            return
                        }
                        throw error
                    }
                }
            }

            let readOutTask = Task.detached {
                try? stdOutPipe.fileHandleForReading.readToEnd()
            }
            let readErrTask = Task.detached {
                try? stdErrPipe.fileHandleForReading.readToEnd()
            }

            let outDataOpt = await readOutTask.value
            let errDataOpt = await readErrTask.value
            _ = try? await writeTask.value

            process.waitUntilExit()

            if timeoutFlag.isTimedOut {
                throw NSError(domain: Constants.actionErrorDomain,
                              code: Int(Constants.actionErrorCode) + 1,
                              userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(Constants.scriptTimeout)) seconds"])
            }

            let outData = outDataOpt ?? Data()
            let errData = errDataOpt ?? Data()

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
    }
}
