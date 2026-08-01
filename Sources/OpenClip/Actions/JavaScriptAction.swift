import Foundation
import JavaScriptCore
import Core

@MainActor
public struct JavaScriptAction: ConfigurableAction {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let configurationViewID: String
    public let preferenceIconName: String
    public let scriptCode: String
    public let actionOptions: [ExtensionOption]

    public init(
        id: String,
        title: String,
        iconSymbol: String = "terminal",
        scriptCode: String,
        options: [ExtensionOption] = []
    ) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconSymbol)
        self.configurationViewID = id
        self.preferenceIconName = iconSymbol
        self.scriptCode = scriptCode
        self.actionOptions = options
    }

    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }

    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        
        let jsContext = JSContext()!
        
        // Populate options dictionary
        var optionsDict: [String: Any] = [:]
        for opt in actionOptions {
            let key = "action.\(id).option.\(opt.identifier)"
            optionsDict[opt.identifier] = UserDefaults.standard.string(forKey: key) ?? (opt.defaultValue ?? "")
        }
        
        var openURLResult: URL?
        var pasteTextResult: String?
        
        // Expose native openclip JS bridge object
        let openclipBridge: @convention(block) () -> [String: Any] = {
            return [
                "input": ["text": text],
                "options": optionsDict
            ]
        }
        
        let openUrlBlock: @convention(block) (String) -> Void = { urlString in
            if let url = URL(string: urlString) {
                openURLResult = url
            }
        }
        
        let pasteTextBlock: @convention(block) (String) -> Void = { textString in
            pasteTextResult = textString
        }
        
        jsContext.setObject(openclipBridge(), forKeyedSubscript: "openclip" as NSString)
        jsContext.evaluateScript("openclip.openUrl = function(u) { _openUrl(u); };")
        jsContext.evaluateScript("openclip.openURL = function(u) { _openUrl(u); };")
        jsContext.evaluateScript("openclip.pasteText = function(t) { _pasteText(t); };")
        jsContext.setObject(openUrlBlock, forKeyedSubscript: "_openUrl" as NSString)
        jsContext.setObject(pasteTextBlock, forKeyedSubscript: "_pasteText" as NSString)
        
        // Execute JS script
        let wrappedScript = """
        (function() {
            var selection = openclip.input.text;
            var options = openclip.options;
            \(scriptCode)
            if (typeof action === 'function') {
                return action(selection, options);
            }
            if (typeof main === 'function') {
                return main(selection, options);
            }
            return null;
        })();
        """
        
        let jsResult = jsContext.evaluateScript(wrappedScript)
        
        if let url = openURLResult {
            return .openURL(url)
        }
        
        if let pasteText = pasteTextResult {
            return .paste(pasteText)
        }
        
        if let resultString = jsResult?.toString(), resultString != "undefined", resultString != "null" {
            return .copy(resultString)
        }
        
        return .success
    }
}
