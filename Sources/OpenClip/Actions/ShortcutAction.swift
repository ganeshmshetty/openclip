// ShortcutAction.swift
// OpenClip
//
// Implements the `shortcut` extension runtime (Phase 8). The action holds the Shortcuts.app
// shortcut name supplied by the manifest's `shortcutName` field and returns `.runShortcut` with
// the current selection as input; the effect door runs `/usr/bin/shortcuts run` under the shared
// subprocess watchdog. Enablement and match resolution delegate to the shared ActionVisibility
// evaluator when rules are attached; otherwise the default requires a non-blank selection.
import Foundation
import Core

public struct ShortcutAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let shortcutName: String
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?

    public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("command"),
        shortcutName: String,
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutName = shortcutName
        self.chrome = chrome ?? ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
        self.rules = rules
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return ActionVisibility.isEnabled(requirements: rules.requirements, legacyRegex: rules.legacyRegex, context: context).match
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .runShortcut(name: shortcutName, input: context.selection.text)
    }
}