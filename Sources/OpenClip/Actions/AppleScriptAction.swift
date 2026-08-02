// AppleScriptAction.swift
// OpenClip
//
// Implements action execution for AppleScript snippets and files using macOS NSAppleScript automation.
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
    public let chrome: ActionChrome

    nonisolated public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("applescript"),
        appleScriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.configurationViewID = id
        self.preferenceIconName = switch icon {
        case .symbol(let name): name
        case .local(let url): url.lastPathComponent
        case .url(let url): url.absoluteString
        case .text(let txt): txt
        }
        self.appleScriptCode = appleScriptCode
        self.actionOptions = options
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
    }

    nonisolated public init(
        id: String,
        title: String,
        iconSymbol: String,
        appleScriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil
    ) {
        self.init(id: id, title: title, icon: .symbol(iconSymbol), appleScriptCode: appleScriptCode, options: options, chrome: chrome)
    }

    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }

    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let rawText = context.selection.text
        let text = rawText.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptWithVars = TextPlaceholderEngine.replacePlaceholders(in: appleScriptCode, with: rawText, urlEncode: false)
        
        let fullScript = """
        global OPENCLIP_TEXT, openclip_text
        set OPENCLIP_TEXT to "\(text)"
        set openclip_text to "\(text)"
        \(scriptWithVars)
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
