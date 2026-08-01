import Foundation
import Core

@MainActor
public struct AppleScriptAction: ConfigurableAction {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let configurationViewID: String
    public let preferenceIconName: String
    public let appleScriptCode: String
    public let actionOptions: [ExtensionOption]

    public init(
        id: String,
        title: String,
        iconSymbol: String = "applescript",
        appleScriptCode: String,
        options: [ExtensionOption] = []
    ) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconSymbol)
        self.configurationViewID = id
        self.preferenceIconName = iconSymbol
        self.appleScriptCode = appleScriptCode
        self.actionOptions = options
    }

    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }

    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.replacingOccurrences(of: "\"", with: "\\\"")
        
        let fullScript = """
        set POPCLIP_TEXT to "\(text)"
        set popclip text to "\(text)"
        \(appleScriptCode)
        """
        
        return await Task.detached {
            var errorDict: NSDictionary?
            if let scriptObject = NSAppleScript(source: fullScript) {
                let output = scriptObject.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    return .failure(NSError(domain: "AppleScriptAction", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]))
                }
                if let str = output.stringValue, !str.isEmpty {
                    return .copy(str)
                }
            }
            return .success
        }.value
    }
}
