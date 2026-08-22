// AppleScriptAction.swift
// OpenClip
//
// Implements action execution for AppleScript snippets and files. Scripts run as killable
// `osascript` subprocesses via AppleScriptRunner (a bounded off-main strategy) so a hung
// `tell application` cannot park a cooperative-pool thread; the watchdog reaps it at
// Constants.scriptTimeout. Enablement and match resolution delegate to the shared ActionVisibility
// evaluator when rules are attached.
import Foundation
import Core

@MainActor
public struct AppleScriptAction: ConfigurableAction {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let preferenceIconName: String
    public let appleScriptCode: String
    public let actionOptions: [ExtensionOption]
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?

    nonisolated public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("applescript"),
        appleScriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.preferenceIconName = switch icon {
        case .symbol(let name): name
        case .local(let url): url.lastPathComponent
        case .url(let url): url.absoluteString
        case .text(let txt): txt
        }
        self.appleScriptCode = appleScriptCode
        self.actionOptions = options
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
        self.rules = rules
    }

    nonisolated public init(
        id: String,
        title: String,
        iconSymbol: String,
        appleScriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil
    ) {
        self.init(id: id, title: title, icon: .symbol(iconSymbol), appleScriptCode: appleScriptCode, options: options, chrome: chrome, rules: rules)
    }

    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.isEmpty
        }
        return rules.resolveVisibility(for: context).enabled
    }

    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return rules.resolveVisibility(for: context).match
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Executes the snippet as `osascript`. Returned text is pasted on a primary click; a secondary
    /// click derives copy via delivery (the paste→copy default).
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let rawText = context.selection.text
        let text = Self.escapeAppleScript(rawText)
        let html = Self.escapeAppleScript(context.selection.html ?? "")
        let rtf = Self.escapeAppleScript(context.selection.rtf ?? "")

        let escapedSelection = SelectionContext(
            text: text,
            sourceApp: context.selection.sourceApp,
            cursorPosition: context.selection.cursorPosition,
            mouseDownLocation: context.selection.mouseDownLocation,
            selectionBounds: context.selection.selectionBounds,
            timestamp: context.selection.timestamp,
            appPolicy: context.selection.appPolicy,
            isClipboardFallback: context.selection.isClipboardFallback,
            html: html,
            rtf: rtf
        )

        let escapedMatch = context.match.map { match in
            ActionMatchInfo(
                text: Self.escapeAppleScript(match.text),
                matchedText: Self.escapeAppleScript(match.matchedText),
                captures: match.captures.map { Self.escapeAppleScript($0) },
                sourceBundleID: match.sourceBundleID
            )
        }

        let escapedContext = ActionContext(
            selection: escapedSelection,
            modifiers: context.modifiers,
            match: escapedMatch
        )

        let scriptWithVars = TextPlaceholderEngine.replacePlaceholders(in: appleScriptCode, context: escapedContext, urlEncode: false)
        
        // Inject the selection as top-level `property` declarations rather than top-level `set` statements.
        // AppleScript forbids combining top-level statements with an explicit `on run` handler
        // (error -2752), so the old global/set preamble silently broke any script written with
        // `on run ... end run`. A `property` declaration coexists with BOTH authoring styles.
        let fullScript = """
        property OPENCLIP_TEXT : "\(text)"
        property OPENCLIP_HTML : "\(html)"
        property OPENCLIP_RTF : "\(rtf)"
        \(scriptWithVars)
        """
        
        do {
            let output = try await AppleScriptRunner.shared.run(fullScript)
            return output.isEmpty ? .success : .text(output)
        } catch {
            Log.resultHandler.error("AppleScript action \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            return .failure(NSError(domain: "AppleScriptAction", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
        }
    }
}
