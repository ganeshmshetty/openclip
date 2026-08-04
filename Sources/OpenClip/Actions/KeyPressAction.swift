// KeyPressAction.swift
// OpenClip
//
// Implements the `keyPress` extension runtime (Phase 8). The action holds a parsed KeyPressSpec
// and returns `.keyPress(spec)` so the effect door can post the synthetic keystroke to the
// frontmost app; Core owns only the parse + model (Key→CGKeyCode mapping lives in the handler).
// Enablement and match resolution delegate to the shared ActionVisibility evaluator when rules
// are attached; otherwise the default requires a non-blank selection.
import Foundation
import Core

public struct KeyPressAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let spec: KeyPressSpec
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?

    public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("keyboard"),
        spec: KeyPressSpec,
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.spec = spec
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
        return .keyPress(spec)
    }
}