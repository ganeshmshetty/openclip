// ShellProcessRunner.swift
// OpenClip
//
// Shared subprocess executor for the shell and script runtimes. Pipes are read via GCD readability
// handlers so a stuck child cannot wedge the cooperative pool; stdin is closed up front so scripts
// always see EOF. Non-zero exits throw with stderr as the message.
import Foundation
import UniformTypeIdentifiers
#if canImport(Darwin)
import Darwin
#endif

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

/// Lets Task cancellation terminate the process group immediately.
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

/// Reads a pipe via GCD so a child (or grandchild) holding the fd open cannot block the caller.
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

    /// Waits at most `grace` seconds for EOF, then drains and closes.
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

/// Reference box so `ScriptJSONOutput` can contain itself via `effect`.
final class ScriptJSONEffect: Decodable {
    let value: ScriptJSONOutput
    init(from decoder: Decoder) throws {
        self.value = try ScriptJSONOutput(from: decoder)
    }
}

/// Shell stdout JSON protocol; all fields except `type` are optional.
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
    let path: String?
    let url: String?
    let data: String?
    let filename: String?
    let mimeType: String?
    let action: String?
    let presentation: String?
}

/// Returns nil when stdout is not JSON; an unknown `type` maps to `.success`.
public enum ShellResultMapper {
    public static func actionResult(from stdout: String, actionID: String) -> ActionResult? {
        guard let data = stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScriptJSONOutput.self, from: data) else {
            return nil
        }
        return map(decoded, actionID: actionID)
    }

    public static func detectFileResult(from stdout: String) -> ActionResult? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            return nil
        }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file://") else {
            return nil
        }
        guard let url = parseExistingFileURL(from: trimmed) else {
            return nil
        }
        return .file(FileOutputPayload(url: url, filename: url.lastPathComponent, isTemporary: false))
    }

    public static func parseFileURL(from rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.isFileURL {
                return url
            }
            let stripped = String(trimmed.dropFirst("file://".count))
            let expanded = (stripped as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    public static func parseExistingFileURL(from rawPath: String) -> URL? {
        guard let url = parseFileURL(from: rawPath) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        return url
    }

    public static func writeTemporaryOutput(data: Data, filename: String?, mimeType: String?) -> URL? {
        let dir = Constants.outputsDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let resolvedFilename: String
        if let rawName = filename?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let sanitized = (rawName as NSString).lastPathComponent
            if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
                let ext = extensionForMimeType(mimeType) ?? "bin"
                resolvedFilename = "output-\(UUID().uuidString).\(ext)"
            } else {
                resolvedFilename = sanitized
            }
        } else {
            let ext = extensionForMimeType(mimeType) ?? "bin"
            resolvedFilename = "output-\(UUID().uuidString).\(ext)"
        }
        let fileURL = dir.appendingPathComponent(resolvedFilename)
        guard Constants.isPathSafe(destinationURL: fileURL, baseDirectory: dir) else {
            return nil
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func extensionForMimeType(_ mime: String?) -> String? {
        guard let mime = mime?.lowercased() else { return nil }
        switch mime {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        case "application/pdf": return "pdf"
        case "application/json": return "json"
        case "text/plain": return "txt"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "video/mp4": return "mp4"
        case "application/zip": return "zip"
        case "text/markdown", "text/x-markdown": return "md"
        case "text/csv": return "csv"
        case "text/html": return "html"
        case "text/xml", "application/xml": return "xml"
        case "text/yaml", "application/yaml", "application/x-yaml": return "yaml"
        case "application/rtf", "text/rtf": return "rtf"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        default: return UTType(mimeType: mime)?.preferredFilenameExtension
        }
    }

    private static func resolveFileURL(from output: ScriptJSONOutput) -> URL? {
        if let base64String = output.data, let data = Data(base64Encoded: base64String) {
            return writeTemporaryOutput(data: data, filename: output.filename, mimeType: output.mimeType)
        }
        let rawPath = output.path ?? output.url ?? output.value
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return nil
        }
        return parseExistingFileURL(from: rawPath)
    }

    private static func mapFileOutput(_ output: ScriptJSONOutput) -> ActionResult {
        guard let targetURL = resolveFileURL(from: output) else {
            return .toast(StatusFeedback(message: String(localized: "File not found"), style: .error))
        }
        let isTemp = output.data != nil
        let payload = FileOutputPayload(
            url: targetURL,
            filename: output.filename ?? targetURL.lastPathComponent,
            mimeType: output.mimeType,
            isTemporary: isTemp
        )
        if let action = output.action?.lowercased() {
            switch action {
            case "copy", "copyfile":
                return .copyFile(targetURL)
            case "save", "savefile":
                return .saveFile(targetURL)
            default:
                return .file(payload)
            }
        }
        return .file(payload)
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
        case "text":
            guard let value = output.value else { return .success }
            guard let rawPresentation = output.presentation else { return .text(value) }
            return .presentedText(value, ResultPresentation(rawValue: rawPresentation) ?? .plain)
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
        case Constants.actionTypeFile, "file":
            return mapFileOutput(output)
        case Constants.actionTypeCopyFile, "copyFile", "copy-file":
            if let targetURL = resolveFileURL(from: output) {
                return .copyFile(targetURL)
            }
            return .toast(StatusFeedback(message: String(localized: "File not found"), style: .error))
        case Constants.actionTypeSaveFile, "saveFile", "save-file":
            if let targetURL = resolveFileURL(from: output) {
                return .saveFile(targetURL)
            }
            return .toast(StatusFeedback(message: String(localized: "File not found"), style: .error))
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

/// Runs a subprocess to completion or the watchdog timeout. Throws on non-zero exit and on timeout.
public enum ShellProcessRunner {
    public struct Invocation: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        /// Text written to the subprocess's stdin (then the pipe is closed). nil leaves stdin unseeded.
        public var stdinText: String?
        /// nil runs with no watchdog; the subprocess lives until it exits or is cancelled.
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

        // Snapshot descendants before terminate(): orphans reparent to launchd and are lost.
        let descendants = descendantSnapshots(of: pid)

        process.terminate()
        if getpgid(pid) == pid {
            kill(-pid, SIGTERM)
        }
        for snapshot in descendants {
            guard isProcessPresent(snapshot.pid),
                  processStartTime(pid: snapshot.pid) == snapshot.startTime else { continue }
            kill(snapshot.pid, SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + fallbackDelay) {
            if process.isRunning, process.processIdentifier == pid {
                process.terminate()
                if getpgid(pid) == pid {
                    kill(-pid, SIGKILL)
                } else {
                    kill(pid, SIGKILL)
                }
            }
            for snapshot in descendants {
                guard isProcessPresent(snapshot.pid),
                      processStartTime(pid: snapshot.pid) == snapshot.startTime else { continue }
                kill(snapshot.pid, SIGKILL)
            }
        }
    }

    private struct ProcessStartTime: Equatable, Sendable {
        let sec: UInt64
        let usec: UInt64
    }

    private struct DescendantSnapshot: Sendable {
        let pid: pid_t
        let startTime: ProcessStartTime
    }

    private static func descendantSnapshots(of root: pid_t) -> [DescendantSnapshot] {
        descendantProcessIDs(of: root).compactMap { child in
            guard let startTime = processStartTime(pid: child) else { return nil }
            return DescendantSnapshot(pid: child, startTime: startTime)
        }
    }

    private static func descendantProcessIDs(of root: pid_t) -> [pid_t] {
        let selfPid = getpid()
        var ids: [pid_t] = []
        var queue: [pid_t] = [root]
        var seen: Set<pid_t> = [root]
        var index = 0
        while index < queue.count {
            let parent = queue[index]
            index += 1
            for child in childProcessIDs(of: parent) {
                guard child > 1, child != selfPid, !seen.contains(child) else { continue }
                seen.insert(child)
                ids.append(child)
                queue.append(child)
            }
        }
        return ids
    }

    /// Direct children only, keeping the walk inside our subtree. Buffer keeps slack since the count can grow.
    private static func childProcessIDs(of parent: pid_t) -> [pid_t] {
        var capacity = Int(proc_listchildpids(parent, nil, 0))
        if capacity <= 0 {
            capacity = 8
        }
        capacity += 16
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listchildpids(
                parent,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).filter { $0 > 0 }
    }

    private static func processStartTime(pid: pid_t) -> ProcessStartTime? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return ProcessStartTime(sec: info.pbi_start_tvsec, usec: info.pbi_start_tvusec)
    }

    private static func isProcessPresent(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
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

                // GCD pipe readers never block a cooperative thread, even if the child is stuck.
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
                processBox.set(process)

                if processBox.isCancelled {
                    process.waitUntilExit()
                    throw CancellationError()
                }

                // GCD-timer watchdog, armed before the stdin write so a child that never reads
                // stdin is still killed on budget. No explicit timeout means no watchdog.
                let timeoutFlag = TimeoutFlag()
                if let budget = invocation.timeout {
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + budget, leeway: .milliseconds(50))
                    timer.setEventHandler { [weak process] in
                        guard let process, process.isRunning else { return }
                        timeoutFlag.markTimedOut()
                        terminateProcessGroup(process, fallbackDelay: 0.5)
                    }
                    timer.resume()
                    watchdog = timer
                }

                // Seed and close stdin so a script reading it always sees EOF.
                if let textData = invocation.stdinText?.data(using: .utf8) {
                    try? stdInPipe.fileHandleForWriting.write(contentsOf: textData)
                }
                try? stdInPipe.fileHandleForWriting.close()

                process.waitUntilExit()

                if processBox.isCancelled {
                    throw CancellationError()
                }

                if timeoutFlag.isTimedOut, let budget = invocation.timeout {
                    throw NSError(domain: Constants.actionErrorDomain,
                                  code: Int(Constants.actionErrorCode) + 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(budget)) seconds"])
                }

                // Drain before reading buffers: waitUntilExit() can return before the handlers
                // have consumed all output. The defer runs too late for this.
                outReader.finish()
                errReader.finish()

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
