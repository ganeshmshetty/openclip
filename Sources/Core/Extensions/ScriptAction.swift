// ScriptAction.swift
// OpenClip
//
// Implements an action backed by an external script file located in an extension directory.
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when rules
// are attached; perform exports the selection and match data to the subprocess via env vars
// (OPENCLIP_TEXT, OPENCLIP_MATCHED, OPENCLIP_CAPTURE_N, OPENCLIP_BUNDLE_ID).
import Foundation

public struct ScriptAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let scriptURL: URL
    public let rules: ExtensionActionRules?
    
    public let chrome: ActionChrome
    
    public init(id: String, title: String, icon: ActionIcon, scriptURL: URL, chrome: ActionChrome? = nil, rules: ExtensionActionRules? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.scriptURL = scriptURL
        self.rules = rules
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
    }

    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            // Scripts usually need some text, but could be general. We'll enable if there is any selection.
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).match
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        let match = context.match
        let scriptPath = scriptURL.path
        
        return try await Task.detached {
            let process = Process()
            
            let isExecutable = FileManager.default.isExecutableFile(atPath: scriptPath)
            guard isExecutable else {
                throw NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: [NSLocalizedDescriptionKey: "Script is not executable: \(scriptPath)"])
            }
            process.executableURL = URL(fileURLWithPath: scriptPath)
            
            var env = ProcessInfo.processInfo.environment
            env[Constants.envVarText] = text
            env[Constants.envVarMatched] = match?.matchedText ?? text
            if let bundleID = match?.sourceBundleID ?? context.selection.sourceApp.bundleIdentifier {
                env[Constants.envVarBundleID] = bundleID
            }
            if let captures = match?.captures {
                for (index, capture) in captures.enumerated() {
                    env[Constants.envVarCapturePrefix + "\(index + 1)"] = capture
                }
            }
            process.environment = env
            
            let stdOutPipe = Pipe()
            process.standardOutput = stdOutPipe
            
            let stdErrPipe = Pipe()
            process.standardError = stdErrPipe
            
            let stdInPipe = Pipe()
            process.standardInput = stdInPipe
            
            try process.run()
            
            // Watchdog: kill the script if it exceeds the runtime budget so the popup never spins forever.
            // Closing the stdout/stderr read ends sends SIGPIPE to every writer (the script and any
            // backgrounded children that retained a pipe), unblocking the readers below even when a
            // child outlives the shell. A watchdog kill is surfaced as a timeout error.
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
                if let textData = text.data(using: .utf8) {
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
                let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown script error"
                throw NSError(domain: Constants.actionErrorDomain,
                              code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            
            if outData.isEmpty {
                return .success
            }
            
            struct ScriptOutput: Decodable {
                let type: String
                let value: String?
            }
            
            if let decoded = try? JSONDecoder().decode(ScriptOutput.self, from: outData) {
                switch decoded.type {
                case Constants.actionTypePaste:
                    if let value = decoded.value {
                        return .paste(value)
                    }
                case Constants.actionTypeCopy:
                    if let value = decoded.value {
                        return .copy(value)
                    }
                case Constants.actionTypeOpenURL:
                    if let value = decoded.value, let url = URL(string: value) {
                        return .openURL(url)
                    }
                default:
                    break
                }
                return .success
            }
            
            if let str = String(data: outData, encoding: .utf8), !str.isEmpty {
                return .paste(str)
            }
            
            return .success
        }.value
    }
}
