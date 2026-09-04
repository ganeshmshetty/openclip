// ScriptAction.swift
// OpenClip
//
// Implements an action backed by an external script file located in an extension directory.
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when rules
// are attached; perform exports the selection and match data to the subprocess via env vars
// (OPENCLIP_TEXT, OPENCLIP_MATCHED, OPENCLIP_CAPTURE_N, OPENCLIP_BUNDLE_ID, OPENCLIP_ACTION_ID)
// and runs it through the
// shared ShellProcessRunner (one watchdog), then translates stdout JSON via ShellResultMapper and
// returns the raw runtime result (secondary/delivery handling happens downstream).
import Foundation

public struct ScriptAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let scriptURL: URL
    public let rules: ExtensionActionRules?
    
    public let chrome: ActionChrome
    
    public init(id: String, title: String, icon: ActionIcon, scriptURL: URL, chrome: ActionChrome? = nil, rules: ExtensionActionRules? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.scriptURL = scriptURL
        self.rules = rules
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
    }

    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            // Scripts usually need some text, but could be general. We'll enable if there is any selection.
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
        let match = context.match
        let scriptPath = scriptURL.path

        let isExecutable = FileManager.default.isExecutableFile(atPath: scriptPath)
        guard isExecutable else {
            throw NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: [NSLocalizedDescriptionKey: "Script is not executable: \(scriptPath)"])
        }

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
        env[Constants.envVarActionID] = id
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
            executableURL: scriptURL,
            arguments: [],
            environment: env,
            stdinText: text
        ))

        // Raw runtime result: JSON stdout wins, plain-text stdout is implicitly returned text
        // (governed by the user's per-click preference), empty stdout succeeds.
        let raw: ActionResult
        if let jsonResult = ShellResultMapper.actionResult(from: output.stdout, actionID: id) {
            raw = jsonResult
        } else if !output.stdout.isEmpty {
            raw = .text(output.stdout)
        } else {
            raw = .success
        }

        return raw
    }
}
