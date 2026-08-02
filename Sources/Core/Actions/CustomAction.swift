// CustomAction.swift
// OpenClip
//
// Defines the domain model for user-created custom actions, supporting web searches, text templates, and shell scripts.
// Implements the Action protocol to allow user-defined operations to be presented and executed seamlessly.
import Foundation

public enum CustomActionType: Codable, Sendable, Equatable, Hashable {
    case webSearch(urlTemplate: String)
    case textSnippet(template: String)
    case shellScript(script: String, replaceSelection: Bool)
}

public struct CustomAction: Action, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let iconName: String
    public let type: CustomActionType
    
    public init(id: String, title: String, iconName: String, type: CustomActionType) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.type = type
    }
    
    public var icon: ActionIcon {
        return .symbol(iconName)
    }
    
    public var chrome: ActionChrome {
        ActionChrome(badge: .custom, rowStyle: .standard, popupBehavior: .perform, source: .custom)
    }

    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        switch type {
        case .webSearch(let urlTemplate):
            let urlString = TextPlaceholderEngine.replacePlaceholders(in: urlTemplate, with: text, urlEncode: true)
            if let url = URL(string: urlString) {
                return .openURL(url)
            }
            return .none
            
        case .textSnippet(let template):
            let formatted = TextPlaceholderEngine.replacePlaceholders(in: template, with: text, urlEncode: false)
            return .paste(formatted) // mapped from replaceSelection(formatted)
            
        case .shellScript(let script, let replaceSelection):
            return try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", script]
                
                var env = ProcessInfo.processInfo.environment
                env["OPENCLIP_TEXT"] = text
                process.environment = env
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                let once = OnceGate()
                let timeoutFlag = TimeoutFlag()
                let resume: @Sendable (Result<ActionResult, Error>) -> Void = { result in
                    guard once.claim() else { return }
                    switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                
                process.terminationHandler = { p in
                    let data = (try? pipe.fileHandleForReading.readDataToEndOfFile()) ?? Data()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if timeoutFlag.isTimedOut {
                        // A watchdog kill (or an unblocked read after a watchdog close) is a
                        // failure, not a success: resuming with empty/partial output could erase
                        // the selection when replaceSelection is true.
                        resume(.failure(NSError(domain: Constants.actionErrorDomain,
                                                code: Int(Constants.actionErrorCode) + 1,
                                                userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(Constants.scriptTimeout)) seconds"])))
                    } else if replaceSelection {
                        resume(.success(.paste(output)))
                    } else {
                        resume(.success(.copy(output)))
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    resume(.failure(error))
                    return
                }
                
                // Watchdog: kill the script if it exceeds the runtime budget so the popup never
                // spins forever. Closing the stdout read end sends SIGPIPE to the shell and any
                // backgrounded children that retained the pipe, unblocking the termination handler
                // even when a child outlives the shell. A timeout is always treated as a failure.
                let timeout = Constants.scriptTimeout
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak process] in
                    guard !timeoutFlag.isTimedOut else { return }
                    timeoutFlag.markTimedOut()
                    try? pipe.fileHandleForReading.close()
                    if process?.isRunning == true {
                        process?.terminate()
                    }
                }
            }
        }
    }
}

/// Thread-safe guard that allows exactly one caller to proceed.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

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
