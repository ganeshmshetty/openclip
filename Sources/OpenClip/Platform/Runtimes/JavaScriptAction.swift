// JavaScriptAction.swift
// OpenClip
//
// Implements action execution for JavaScript snippets using JavaScriptCore, reading options via the
// Settings Door. Enablement and match resolution delegate to the shared ActionVisibility evaluator
// when rules are attached. perform short-circuits to `.openConfiguration` when a declaratively
// required option has no resolved value (Phase 7), then delegates to OpenClipJSHost (the dedicated,
// testable bridge that exposes the read-only openclip.* surface) for the RAW runtime result.
// Secondary/delivery handling happens downstream via the action's declared `delivery`.
import Foundation
import JavaScriptCore
import Core

@MainActor
public struct JavaScriptAction: ConfigurableAction {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let preferenceIconName: String
    public let scriptCode: String
    public let actionOptions: [ExtensionOption]
    public let chrome: ActionChrome
    public let optionStore: any ActionOptionReading
    public let rules: ExtensionActionRules?
    /// When true the JS host runs asynchronously (promise awaiting + fetch polyfill + watchdog).
    public let isAsync: Bool
    /// The extension package directory. When non-nil the JS host runs in module mode
    /// (`require`/multi-file); nil means inline `scriptCode` keeps the legacy single-file behavior.
    public let packageDirectory: URL?
    /// The entry script directory. When nil, defaults to packageDirectory.
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
        // Phase 7: a declaratively-required option with no resolved value short-circuits to
        // configuration BEFORE any JS runs. Distinct from the runtime `openclip.requireConfiguration`
        // call (a script-time request); this is the manifest `requiredOptions` auto-check and must
        // not be duplicated inside OpenClipJSHost.
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
            packageDirectory: packageDirectory,
            entryDirectory: entryDirectory,
            pasteboardContent: OpenClipJSHost.PasteboardContent.read()
        )
        return try await OpenClipJSHost().run(request)
    }
}
