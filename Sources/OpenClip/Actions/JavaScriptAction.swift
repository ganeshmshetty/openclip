// JavaScriptAction.swift
// OpenClip
//
// Implements action execution for JavaScript snippets using JavaScriptCore, reading options via the Settings Door.
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when rules are attached.
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
    public let chrome: ActionChrome
    public let optionStore: any ActionOptionReading
    public let rules: ExtensionActionRules?

    nonisolated public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("terminal"),
        scriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        optionStore: any ActionOptionReading = SettingsActionOptionStore(),
        rules: ExtensionActionRules? = nil
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
        self.scriptCode = scriptCode
        self.actionOptions = options
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
        self.optionStore = optionStore
        self.rules = rules
    }

    nonisolated public init(
        id: String,
        title: String,
        iconSymbol: String,
        scriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        optionStore: any ActionOptionReading = SettingsActionOptionStore(),
        rules: ExtensionActionRules? = nil
    ) {
        self.init(id: id, title: title, icon: .symbol(iconSymbol), scriptCode: scriptCode, options: options, chrome: chrome, optionStore: optionStore, rules: rules)
    }

    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.isEmpty
        }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).enabled
    }

    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).match
    }

    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        
        let jsContext = JSContext()!
        
        // Populate options dictionary
        var optionsDict: [String: Any] = [:]
        for opt in actionOptions {
            optionsDict[opt.identifier] = optionStore.stringValue(actionID: id, option: opt)
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
        
        let showNotificationBlock: @convention(block) (String, String) -> Void = { title, message in
            let userNotification = NSUserNotification()
            userNotification.title = title
            userNotification.informativeText = message
            NSUserNotificationCenter.default.deliver(userNotification)
        }
        
        jsContext.setObject(openclipBridge(), forKeyedSubscript: "openclip" as NSString)
        jsContext.evaluateScript("openclip.openUrl = function(u) { _openUrl(u); };")
        jsContext.evaluateScript("openclip.openURL = function(u) { _openUrl(u); };")
        jsContext.evaluateScript("openclip.pasteText = function(t) { _pasteText(t); };")
        jsContext.evaluateScript("openclip.showNotification = function(title, msg) { _showNotification(title, msg); };")
        jsContext.setObject(openUrlBlock, forKeyedSubscript: "_openUrl" as NSString)
        jsContext.setObject(pasteTextBlock, forKeyedSubscript: "_pasteText" as NSString)
        jsContext.setObject(showNotificationBlock, forKeyedSubscript: "_showNotification" as NSString)
        
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
