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
            
            // Determine if the script is executable directly or if we need to run via bash
            // We'll just run it directly if it's executable, otherwise bash
            let isExecutable = FileManager.default.isExecutableFile(atPath: scriptPath)
            if isExecutable {
                process.executableURL = URL(fileURLWithPath: scriptPath)
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath]
            }
            
            var env = ProcessInfo.processInfo.environment
            env["POPCLIP_TEXT"] = text
            process.environment = env
            
            let stdOutPipe = Pipe()
            process.standardOutput = stdOutPipe
            
            let stdErrPipe = Pipe()
            process.standardError = stdErrPipe
            
            let stdInPipe = Pipe()
            process.standardInput = stdInPipe
            
            if let textData = text.data(using: .utf8) {
                try stdInPipe.fileHandleForWriting.write(contentsOf: textData)
                try stdInPipe.fileHandleForWriting.close()
            }
            
            try process.run()
            process.waitUntilExit()
            
            let outData = try stdOutPipe.fileHandleForReading.readToEnd() ?? Data()
            let errData = try stdErrPipe.fileHandleForReading.readToEnd() ?? Data()
            
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
            
            do {
                let decoded = try JSONDecoder().decode(ScriptOutput.self, from: outData)
                switch decoded.type {
                case "paste":
                    if let value = decoded.value {
                        return .paste(value)
                    }
                case "copy":
                    if let value = decoded.value {
                        return .copy(value)
                    }
                case "openURL":
                    if let value = decoded.value, let url = URL(string: value) {
                        return .openURL(url)
                    }
                default:
                    break
                }
                return .success
            } catch {
                return .failure(error)
            }
        }.value
    }
}
