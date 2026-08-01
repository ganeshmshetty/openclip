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
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        switch type {
        case .webSearch(let urlTemplate):
            if let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: urlTemplate.replacingOccurrences(of: "{text}", with: encodedText)) {
                return .openURL(url)
            }
            return .none
            
        case .textSnippet(let template):
            let formatted = template.replacingOccurrences(of: "{text}", with: text)
            return .paste(formatted) // mapped from replaceSelection(formatted)
            
        case .shellScript(let script, let replaceSelection):
            return try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", script]
                
                var env = ProcessInfo.processInfo.environment
                env["POPCLIP_TEXT"] = text
                process.environment = env
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                process.terminationHandler = { p in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if replaceSelection {
                        continuation.resume(returning: .paste(output)) // mapped from replaceSelection(output)
                    } else {
                        continuation.resume(returning: .copy(output)) // mapped from copyToClipboard(output)
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
