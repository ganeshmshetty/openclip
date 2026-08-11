// JavaScriptCanvasAction.swift
// OpenClip
//
// Implements the manifest `type: "canvas"` extension action (spec §5.1). perform does NOT run the
// script — it returns a `.showCanvas` mount request; the engine (JavaScriptCanvasEngine) evaluates
// it, arms the session, and every interactive dispatch re-renders the tree. Options are resolved
// via the Settings Door into `openclip.options`, and the missing-required-options short-circuit
// mirrors JavaScriptAction (Phase 7) before any mount request is built.
import Foundation
import Core

@MainActor
public struct JavaScriptCanvasAction: ConfigurableAction {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let preferenceIconName: String
    public let scriptCode: String
    public let actionOptions: [ExtensionOption]
    public let chrome: ActionChrome
    public let optionStore: any ActionOptionReading
    public let rules: ExtensionActionRules?
    /// When true the canvas script runs asynchronously (promise awaiting + fetch polyfill + watchdog).
    public let isAsync: Bool

    nonisolated public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("square.grid.2x2"),
        scriptCode: String,
        options: [ExtensionOption] = [],
        chrome: ActionChrome? = nil,
        optionStore: any ActionOptionReading = SettingsActionOptionStore(),
        rules: ExtensionActionRules? = nil,
        isAsync: Bool = false
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
        isAsync: Bool = false
    ) {
        self.init(id: id, title: title, icon: .symbol(iconSymbol), scriptCode: scriptCode, options: options, chrome: chrome, optionStore: optionStore, rules: rules, isAsync: isAsync)
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
        // configuration BEFORE any canvas is mounted. Distinct from the runtime
        // `openclip.requireConfiguration` call (a script-time request); this is the manifest
        // `requiredOptions` auto-check and must not be duplicated inside the canvas engine.
        let missing = ActionVisibility.missingRequiredOptions(
            requirements: rules?.requirements,
            options: actionOptions,
            optionStore: optionStore,
            actionID: id
        )
        if !missing.isEmpty {
            return .openConfiguration(ConfigurationRequest(
                actionID: id,
                reason: missing.count == 1 ? "Required option not set." : "Required options not set.",
                missingOptionIDs: missing
            ))
        }

        let optionValues = Dictionary(actionOptions.map { option in
            (option.identifier, JSONValue.string(optionStore.stringValue(actionID: id, option: option)))
        }, uniquingKeysWith: { _, latest in latest })
        let match = context.match ?? matchInfo(for: context)
        let request = CanvasMountRequest(
            initialState: CanvasSessionState(),
            input: context.selection.text,
            captures: match?.captures ?? [],
            sourceApp: context.selection.sourceApp,
            optionValues: optionValues,         // openclip.options in the bridge (empty → {})
            preferredSize: nil,                 // declared at runtime via openclip.showContent(tree, {size})
            scriptCode: scriptCode,
            isAsync: isAsync
        )
        return .showCanvas(request, CanvasHeader(title: title, icon: preferenceIconName))
    }
}
