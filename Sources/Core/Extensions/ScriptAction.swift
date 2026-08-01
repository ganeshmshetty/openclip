import Foundation

public struct ScriptAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let scriptURL: URL
    
    public init(id: String, title: String, icon: ActionIcon, scriptURL: URL) {
        self.id = id
        self.title = title
        self.icon = icon
        self.scriptURL = scriptURL
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        // Scripts usually need some text, but could be general. We'll enable if there is any selection.
        // In a more robust system, we would check the manifest's requirements.
        return true 
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
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
            env["OPENCLIP_TEXT"] = text
            process.environment = env
            
            let stdOutPipe = Pipe()
            process.standardOutput = stdOutPipe
            
            let stdErrPipe = Pipe()
            process.standardError = stdErrPipe
            
            let stdInPipe = Pipe()
            process.standardInput = stdInPipe
            
            try process.run()
            
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
                try stdOutPipe.fileHandleForReading.readToEnd()
            }
            
            let readErrTask = Task.detached {
                try stdErrPipe.fileHandleForReading.readToEnd()
            }
            
            let outDataOpt = try await readOutTask.value
            let errDataOpt = try await readErrTask.value
            _ = try await writeTask.value
            
            process.waitUntilExit()
            
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
