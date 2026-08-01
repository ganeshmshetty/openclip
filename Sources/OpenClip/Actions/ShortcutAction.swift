import Foundation
import Core

@MainActor
public struct ShortcutAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let shortcutName: String
    
    public init(id: String, title: String, iconSymbol: String = "bolt.fill", shortcutName: String) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconSymbol)
        self.shortcutName = shortcutName
    }
    
    public func isEnabled(for context: ActionContext) -> Bool {
        return true
    }
    
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcutName]
        
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = inputPipe
        
        if let data = context.selection.text.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try? inputPipe.fileHandleForWriting.close()
        }
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return .paste(output)
        }
        
        return .success
    }
}
