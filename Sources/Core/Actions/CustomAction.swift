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
    case openURL(urlTemplate: String)
    case textSnippet(template: String)
    case shellScript(script: String, replaceSelection: Bool)

    /// Backward compatibility helper for legacy call sites and tests.
    public static func webSearch(urlTemplate: String) -> CustomActionType {
        .openURL(urlTemplate: urlTemplate)
    }

    private enum CodingKeys: String, CodingKey {
        case openURL
        case webSearch
        case textSnippet
        case shellScript
    }

    private struct URLParams: Codable {
        let urlTemplate: String
    }

    private struct SnippetParams: Codable {
        let template: String
    }

    private struct ShellParams: Codable {
        let script: String
        let replaceSelection: Bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.openURL) {
            let params = try container.decode(URLParams.self, forKey: .openURL)
            self = .openURL(urlTemplate: params.urlTemplate)
        } else if container.contains(.webSearch) {
            let params = try container.decode(URLParams.self, forKey: .webSearch)
            self = .openURL(urlTemplate: params.urlTemplate)
        } else if container.contains(.textSnippet) {
            let params = try container.decode(SnippetParams.self, forKey: .textSnippet)
            self = .textSnippet(template: params.template)
        } else if container.contains(.shellScript) {
            let params = try container.decode(ShellParams.self, forKey: .shellScript)
            self = .shellScript(script: params.script, replaceSelection: params.replaceSelection)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown CustomActionType"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .openURL(let urlTemplate):
            try container.encode(URLParams(urlTemplate: urlTemplate), forKey: .openURL)
        case .textSnippet(let template):
            try container.encode(SnippetParams(template: template), forKey: .textSnippet)
        case .shellScript(let script, let replaceSelection):
            try container.encode(ShellParams(script: script, replaceSelection: replaceSelection), forKey: .shellScript)
        }
    }
}

public struct CustomAction: ConfigurableAction, Codable, Sendable, Equatable {
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
        ActionIcon.resolve(from: iconName)
    }

    public var preferenceIconName: String {
        iconName
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
        case .openURL(let urlTemplate):
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

