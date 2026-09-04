// CustomAction.swift
// OpenClip
//
// Defines the domain model for user-created custom actions, supporting web searches, text templates,
// and shell scripts. Implements the Action protocol to allow user-defined operations to be presented
// and executed seamlessly. The manifest shellInline/textSnippet paths attach ExtensionActionRules so
// declarative visibility flows through the shared evaluator here too, and the factory stamps
// `.extensionPkg` chrome so GUI-created actions share the extension trash path. All three type cases
// return their raw runtime result; the shellScript case runs through the shared ShellProcessRunner
// (one watchdog) with `replaceSelection` deciding paste-vs-copy for plain-text stdout.
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
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?
    
    public init(
        id: String,
        title: String,
        iconName: String,
        type: CustomActionType,
        chrome: ActionChrome = ActionChrome(badge: .custom, rowStyle: .standard, popupBehavior: .perform, source: .custom),
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.type = type
        self.chrome = chrome
        self.rules = rules
    }
    
    public var icon: ActionIcon {
        return .symbol(iconName)
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return rules.resolveVisibility(for: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return rules.resolveVisibility(for: context).match
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        let raw: ActionResult
        switch type {
        case .webSearch(let urlTemplate):
            let urlString = TextPlaceholderEngine.replacePlaceholders(in: urlTemplate, context: context, urlEncode: true)
            if let url = URL(string: urlString) {
                raw = .openURL(url)
            } else {
                raw = .none
            }

        case .textSnippet(let template):
            let formatted = TextPlaceholderEngine.replacePlaceholders(in: template, context: context, urlEncode: false)
            raw = .text(formatted) // implicitly returned text, governed by the user's per-click preference

        case .shellScript(let script, let replaceSelection):
            let match = context.match

            var env = ProcessInfo.processInfo.environment
            env[Constants.envVarText] = text
            env.removeValue(forKey: Constants.envVarHTML)
            env.removeValue(forKey: Constants.envVarRTF)
            if let html = context.selection.html {
                env[Constants.envVarHTML] = html
            }
            if let rtf = context.selection.rtf {
                env[Constants.envVarRTF] = rtf
            }
            env[Constants.envVarMatched] = match?.matchedText ?? text
            if let bundleID = match?.sourceBundleID ?? context.selection.sourceApp.bundleIdentifier {
                env[Constants.envVarBundleID] = bundleID
            }
            if let captures = match?.captures {
                for (index, capture) in captures.enumerated() {
                    env[Constants.envVarCapturePrefix + "\(index + 1)"] = capture
                }
            }
            env[Constants.envVarLocale] = Locale.current.identifier
            env[Constants.envVarLanguage] = Locale.current.language.languageCode?.identifier ?? "en"

            let output = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", script],
                environment: env,
                stdinText: nil
            ))

            // Raw runtime result: JSON stdout wins; plain-text stdout pastes when replaceSelection
            // is true (replacing the selection) or copies otherwise.
            if let jsonResult = ShellResultMapper.actionResult(from: output.stdout, actionID: id) {
                raw = jsonResult
            } else if !output.stdout.isEmpty {
                raw = replaceSelection ? .paste(output.stdout) : .copy(output.stdout)
            } else {
                raw = .success
            }
        }

        return raw
    }
}

