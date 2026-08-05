// OpenClipJSHost.swift
// OpenClip
//
// Dedicated, testable JavaScriptCore bridge for JS extensions (plan §8, Phase 6). Exposes the full
// read-only `openclip.*` author surface (input/matchedText/captures/app, read-only options, and the
// effect API) and resolves collected effects into a RAW runtime ActionResult via a deterministic
// resolution order — no declarative after/stayVisible translation here (that is
// ActionResultAdapter.apply, applied by the runtime's perform). JS exceptions surface as
// `.showStatus(.error, message)` rather than throwing; Swift-level setup failures may throw.
//
// @MainActor: JSC evaluation stays main-actor bound (matching the previous inline bridge in
// JavaScriptAction). No JSC execution watchdog in v1 (plan §13 — "authors must not block").
// The deprecated NSUserNotification bridge is gone; notifications become a `.notify` result that
// the effect door posts via UNUserNotificationCenter.
import Foundation
import JavaScriptCore
import Core

@MainActor
public final class OpenClipJSHost {
    public struct Request: Sendable {
        public var actionID: String
        public var scriptCode: String
        public var context: ActionContext
        public var options: [ExtensionOption]
        public var optionStore: any ActionOptionReading
        public var rules: ExtensionActionRules

        public init(
            actionID: String,
            scriptCode: String,
            context: ActionContext,
            options: [ExtensionOption],
            optionStore: any ActionOptionReading,
            rules: ExtensionActionRules
        ) {
            self.actionID = actionID
            self.scriptCode = scriptCode
            self.context = context
            self.options = options
            self.optionStore = optionStore
            self.rules = rules
        }
    }

    public struct Collected: Sendable {
        public var openURL: URL?
        public var paste: String?
        public var copy: String?
        public var cut: String?
        public var bubble: BubbleContent?
        public var status: StatusFeedback?
        public var configuration: ConfigurationRequest?
        public var keyPress: KeyPressSpec?
        public var shortcutName: String?
        public var keepVisible: Bool
        public var notification: (title: String, body: String)?
        public var returnValue: String?

        public init() {
            self.keepVisible = false
        }
    }

    /// One side-effecting JS call, kept in call order for `.sequence` resolution.
    private enum Effect {
        case paste(String)
        case copy(String)
        case cut(String)
        case openURL(URL)
        case keyPress(KeyPressSpec)
        case runShortcut(name: String)
        case notify(title: String, body: String)
    }

    public init() {}

    public func run(_ request: Request) throws -> ActionResult {
        let (collected, effects, exceptionMessage) = try evaluate(request)

        // JS exceptions win over any partially-collected effects (do NOT throw for JS exceptions).
        if let exceptionMessage {
            let raw: ActionResult = .showStatus(StatusFeedback(message: exceptionMessage, style: .error))
            return collected.keepVisible ? .keepVisible(raw) : raw
        }

        // Deterministic resolution order (plan §8): configuration > bubble > status-only > effects
        // (in call order, sequence when >1) > function string return > success.
        let raw: ActionResult
        if let configuration = collected.configuration {
            raw = .openConfiguration(configuration)
        } else if let bubble = collected.bubble {
            raw = .showBubble(bubble)
        } else if let status = collected.status, effects.isEmpty {
            raw = .showStatus(status)
        } else if !effects.isEmpty {
            let input = request.context.match?.matchedText ?? request.context.selection.text
            let mapped = effects.map { effectResult($0, input: input) }
            raw = mapped.count == 1 ? mapped[0] : .sequence(mapped)
        } else if let returnValue = collected.returnValue {
            raw = .copy(returnValue)
        } else {
            raw = .success
        }

        // The runtime keepVisible flag wraps the resolved result UNCONDITIONALLY (resolution 3);
        // the declarative stayVisible wrap is narrower and lives in ActionResultAdapter.
        if collected.keepVisible {
            return .keepVisible(raw)
        }
        return raw
    }

    // MARK: - JS evaluation

    private func evaluate(_ request: Request) throws -> (Collected, [Effect], String?) {
        let text = request.context.selection.text
        let matchedText = request.context.match?.matchedText ?? text
        let captures = request.context.match?.captures ?? []

        guard let jsContext = JSContext() else {
            throw NSError(domain: Constants.actionErrorDomain,
                          code: Constants.actionErrorCode,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create JavaScript context"])
        }
        var collected = Collected()
        var effects: [Effect] = []

        // Read-only input context. Options are injected as a plain dictionary (values resolved via
        // the option store); `option(id)` is a functional form over the same dictionary.
        let optionsDict = optionValues(for: request)
        let openclip = makeOpenClipObject(
            in: jsContext,
            text: text,
            matchedText: matchedText,
            captures: captures,
            sourceApp: request.context.selection.sourceApp,
            options: optionsDict
        )

        let pasteBlock: @convention(block) (String) -> Void = { value in
            collected.paste = value
            effects.append(.paste(value))
        }
        let copyBlock: @convention(block) (String) -> Void = { value in
            collected.copy = value
            effects.append(.copy(value))
        }
        let cutBlock: @convention(block) (String) -> Void = { value in
            collected.cut = value
            effects.append(.cut(value))
        }
        let openURLBlock: @convention(block) (String) -> Void = { value in
            guard let url = URL(string: value) else { return } // ignore invalid URLs
            collected.openURL = url
            effects.append(.openURL(url))
        }
        let keyPressBlock: @convention(block) (String, NSArray) -> Void = { key, modifiers in
            let spec = KeyPressSpec(key: key, modifiers: Self.mapModifiers(modifiers))
            collected.keyPress = spec
            effects.append(.keyPress(spec))
        }
        let runShortcutBlock: @convention(block) (String) -> Void = { name in
            collected.shortcutName = name
            effects.append(.runShortcut(name: name))
        }
        let notifyBlock: @convention(block) (String, String) -> Void = { title, message in
            collected.notification = (title: title, body: message)
            effects.append(.notify(title: title, body: message))
        }
        let showStatusBlock: @convention(block) (String, String) -> Void = { message, style in
            collected.status = StatusFeedback(message: message, style: Self.mapStatusStyle(style))
        }
        let showBubbleBlock: @convention(block) (JSValue) -> Void = { value in
            collected.bubble = Self.parseBubble(value)
        }
        let keepVisibleBlock: @convention(block) () -> Void = {
            collected.keepVisible = true
        }
        let requireConfigurationBlock: @convention(block) (JSValue) -> Void = { value in
            collected.configuration = Self.parseConfiguration(value, actionID: request.actionID)
        }

        openclip.setObject(pasteBlock, forKeyedSubscript: "paste" as NSString)
        openclip.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        openclip.setObject(cutBlock, forKeyedSubscript: "cut" as NSString)
        openclip.setObject(openURLBlock, forKeyedSubscript: "openURL" as NSString)
        openclip.setObject(keyPressBlock, forKeyedSubscript: "keyPress" as NSString)
        openclip.setObject(runShortcutBlock, forKeyedSubscript: "runShortcut" as NSString)
        openclip.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)
        openclip.setObject(showStatusBlock, forKeyedSubscript: "showStatus" as NSString)
        openclip.setObject(showBubbleBlock, forKeyedSubscript: "showBubble" as NSString)
        openclip.setObject(keepVisibleBlock, forKeyedSubscript: "keepVisible" as NSString)
        openclip.setObject(requireConfigurationBlock, forKeyedSubscript: "requireConfiguration" as NSString)
        jsContext.setObject(openclip, forKeyedSubscript: "openclip" as NSString)
        jsContext.evaluateScript("openclip.option = function(id) { return openclip.options[id]; }")

        // Preserved wrapped-script shape: define action/main inside an IIFE and dispatch to whichever
        // entry point the author provided (golden + option-store tests depend on this exact shape).
        let wrappedScript = """
        (function() {
            var selection = openclip.input.text;
            var options = openclip.options;
            \(request.scriptCode)
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

        if let exception = jsContext.exception {
            return (collected, effects, exception.toString() ?? "JavaScript exception")
        }

        if let resultString = jsResult?.toString(), resultString != "undefined", resultString != "null" {
            collected.returnValue = resultString
        }

        return (collected, effects, nil)
    }

    private func optionValues(for request: Request) -> [String: String] {
        var values: [String: String] = [:]
        for option in request.options {
            values[option.identifier] = request.optionStore.stringValue(actionID: request.actionID, option: option)
        }
        return values
    }

    private func makeOpenClipObject(
        in jsContext: JSContext,
        text: String,
        matchedText: String,
        captures: [String],
        sourceApp: AppIdentity,
        options: [String: String]
    ) -> JSValue {
        let openclip = JSValue(newObjectIn: jsContext)!

        let input = JSValue(newObjectIn: jsContext)!
        input.setObject(text, forKeyedSubscript: "text")
        input.setObject(matchedText, forKeyedSubscript: "matchedText")
        input.setObject(captures, forKeyedSubscript: "captures")

        let app = JSValue(newObjectIn: jsContext)!
        app.setObject(sourceApp.bundleIdentifier ?? "", forKeyedSubscript: "bundleID")
        app.setObject(sourceApp.localizedName ?? "", forKeyedSubscript: "name")
        input.setObject(app, forKeyedSubscript: "app")

        openclip.setObject(input, forKeyedSubscript: "input")
        openclip.setObject(options, forKeyedSubscript: "options")
        return openclip
    }

    // MARK: - Effect → ActionResult

    private func effectResult(_ effect: Effect, input: String) -> ActionResult {
        switch effect {
        case .paste(let text): return .paste(text)
        case .copy(let text): return .copy(text)
        case .cut(let text): return .cut(text)
        case .openURL(let url): return .openURL(url)
        case .keyPress(let spec): return .keyPress(spec)
        case .runShortcut(let name): return .runShortcut(name: name, input: input)
        case .notify(let title, let body): return .notify(title: title, body: body)
        }
    }

    // MARK: - JS value parsing

    private static func mapModifiers(_ modifiers: NSArray) -> [KeyPressSpec.KeyModifier] {
        modifiers.compactMap { element in
            guard let raw = element as? String else { return nil }
            switch raw.lowercased() {
            case "command": return .command
            case "shift": return .shift
            case "option": return .option
            case "control": return .control
            default: return nil
            }
        }
    }

    private static func mapStatusStyle(_ raw: String) -> StatusFeedback.Style {
        switch raw.lowercased() {
        case "success": return .success
        case "error": return .error
        case "info": return .info
        default: return .info
        }
    }

    /// nil for missing/"undefined"/"null" JS string values.
    private static func stringValue(_ value: JSValue?) -> String? {
        guard let value else { return nil }
        let string = value.toString() ?? ""
        if string.isEmpty || string == "undefined" || string == "null" { return nil }
        return string
    }

    private static func parseConfiguration(_ value: JSValue, actionID: String) -> ConfigurationRequest {
        var reason: String?
        var missing: [String] = []
        if value.isObject {
            reason = stringValue(value.objectForKeyedSubscript("reason"))
            if let missingValue = value.objectForKeyedSubscript("missing"), missingValue.isArray {
                missing = missingValue.toArray()?.compactMap { $0 as? String } ?? []
            }
        }
        return ConfigurationRequest(actionID: actionID, reason: reason, missingOptionIDs: missing)
    }

    private static func parseBubble(_ value: JSValue) -> BubbleContent {
        guard value.isObject else { return BubbleContent() }
        let title = stringValue(value.objectForKeyedSubscript("title"))
        let icon = stringValue(value.objectForKeyedSubscript("icon"))
        let subtitle = stringValue(value.objectForKeyedSubscript("subtitle"))
        let body = stringValue(value.objectForKeyedSubscript("body"))

        var emphasis: BubbleEmphasis = .result
        if let raw = stringValue(value.objectForKeyedSubscript("emphasis")) {
            switch raw.lowercased() {
            case "info": emphasis = .info
            case "menu": emphasis = .menu
            default: emphasis = .result
            }
        }

        var rows: [BubbleRow] = []
        if let rowsValue = value.objectForKeyedSubscript("rows"), rowsValue.isArray {
            let array = rowsValue.toArray() ?? []
            for element in array {
                guard let row = element as? [String: Any],
                      let type = row["type"] as? String, type == "text",
                      let text = row["value"] as? String else { continue }
                rows.append(.text(text))
            }
        }
        if rows.isEmpty, let body, !body.isEmpty {
            rows = [.text(body)]
        }

        var footer: [BubbleOption] = []
        if let footerValue = value.objectForKeyedSubscript("footer"), footerValue.isArray {
            for element in footerValue.toArray() ?? [] {
                if let preset = element as? String {
                    switch preset.lowercased() {
                    case "paste":
                        footer.append(BubbleOption(title: "Paste", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste(body ?? ""))))
                    case "copy":
                        footer.append(BubbleOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy(body ?? ""))))
                    default:
                        break
                    }
                } else if let object = element as? [String: Any] {
                    let optionTitle = object["title"] as? String ?? ""
                    let optionIcon = object["icon"] as? String
                    let action = (object["action"] as? String)?.lowercased()
                    let optionValue = object["value"] as? String ?? body ?? ""
                    switch action {
                    case "paste":
                        footer.append(BubbleOption(title: optionTitle, icon: optionIcon, outcome: .perform(.paste(optionValue))))
                    case "copy":
                        footer.append(BubbleOption(title: optionTitle, icon: optionIcon, outcome: .perform(.copy(optionValue))))
                    default:
                        break
                    }
                }
            }
        }

        return BubbleContent(title: title, icon: icon, subtitle: subtitle, rows: rows, footer: footer, emphasis: emphasis)
    }
}
