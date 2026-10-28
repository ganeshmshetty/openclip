// JavaScriptAction.swift
// OpenClip
//
// Runs JavaScript extension actions. Returns `.openConfiguration` when a required option is unset,
// otherwise delegates to OpenClipJSHost for the raw runtime result.
import Foundation
import JavaScriptCore
import Core

@MainActor
public struct JavaScriptAction: ConfigurableAction, ActionWithRules {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let preferenceIconName: String
    public let scriptCode: String
    public let actionOptions: [ExtensionOption]
    public let chrome: ActionChrome
    public let optionStore: any ActionOptionReading
    public let rules: ExtensionActionRules?
    /// Runs the JS host asynchronously (promise awaiting, fetch, watchdog).
    public let isAsync: Bool
    /// Enables module mode (`require`). Nil keeps the single-file inline script.
    public let packageDirectory: URL?
    /// Defaults to packageDirectory when nil.
    public let entryDirectory: URL?

    nonisolated public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("terminal"),
        scriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        optionStore: any ActionOptionReading = SettingsActionOptionStore(),
        rules: ExtensionActionRules? = nil,
        isAsync: Bool = false,
        packageDirectory: URL? = nil,
        entryDirectory: URL? = nil
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
        self.scriptCode = scriptCode
        self.actionOptions = options
        self.chrome = chrome ?? ActionChrome(badge: .script, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
        self.optionStore = optionStore
        self.rules = rules
        self.isAsync = isAsync
        self.packageDirectory = packageDirectory
        self.entryDirectory = entryDirectory
    }

    nonisolated public init(
        id: String,
        title: String,
        iconSymbol: String,
        scriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        optionStore: any ActionOptionReading = SettingsActionOptionStore(),
        rules: ExtensionActionRules? = nil,
        isAsync: Bool = false,
        packageDirectory: URL? = nil,
        entryDirectory: URL? = nil
    ) {
        self.init(id: id, title: title, icon: .symbol(iconSymbol), scriptCode: scriptCode, options: options, chrome: chrome, optionStore: optionStore, rules: rules, isAsync: isAsync, packageDirectory: packageDirectory, entryDirectory: entryDirectory)
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

    public func perform(_ context: ActionContext) async throws -> ActionResult {
        try await perform(context, timeout: nil)
    }

    /// Inline evaluation passes its shorter UI budget so JavaScriptCore interrupts sync scripts at the same deadline.
    func perform(_ context: ActionContext, timeout: TimeInterval?) async throws -> ActionResult {
        let result = try await execute(context, timeout: timeout)
        // The click delivers the visible text. A view-only preview has nothing to deliver.
        guard chrome.isInlineResult, case .text(let raw) = result else { return result }
        let preview = InlinePreview.resolve(returnedText: raw)
        guard preview.acceptsActivation else { return .none }
        return .text(preview.text)
    }

    /// Inline display value, including swatch, tone, icon, and the view-only flag. Nil when the script did not return text.
    func inlinePreview(_ context: ActionContext, timeout: TimeInterval?) async throws -> InlinePreview? {
        let result = try await execute(context, timeout: timeout)
        guard case .text(let raw) = result else { return nil }
        let preview = InlinePreview.resolve(returnedText: raw)
        guard !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return preview
    }

    private func execute(_ context: ActionContext, timeout: TimeInterval?) async throws -> ActionResult {
        // Manifest `requiredOptions` check, run before any JS. Distinct from the runtime
        // `openclip.requireConfiguration` call, so keep it out of OpenClipJSHost.
        let missing = ActionVisibility.missingRequiredOptions(
            requirements: rules?.requirements,
            options: actionOptions,
            optionStore: optionStore,
            actionID: id
        )
        if !missing.isEmpty {
            return .openConfiguration(ConfigurationRequest(
                actionID: id,
                reason: missing.count == 1 ? String(localized: "Required option not set.") : String(localized: "Required options not set."),
                missingOptionIDs: missing
            ))
        }

        let request = OpenClipJSHost.Request(
            actionID: id,
            scriptCode: scriptCode,
            context: context,
            options: actionOptions,
            optionStore: optionStore,
            rules: rules ?? ExtensionActionRules(),
            isAsync: isAsync,
            isInline: chrome.isInlineResult,
            timeout: timeout,
            packageDirectory: packageDirectory,
            entryDirectory: entryDirectory,
            pasteboardContent: OpenClipJSHost.PasteboardContent.read()
        )
        return try await OpenClipJSHost().run(request)
    }
}
