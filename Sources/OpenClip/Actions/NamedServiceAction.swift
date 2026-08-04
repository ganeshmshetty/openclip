// NamedServiceAction.swift
// OpenClip
//
// Implements the `service` extension runtime (Phase 8). v1 maps the kind to the generic macOS
// share picker (`.showServices(text)`); `serviceName` is reserved for a future named-service
// (`NSPerformService`) invocation and is accepted but unused. Enablement and match resolution
// delegate to the shared ActionVisibility evaluator when rules are attached; otherwise the
// default requires a non-blank selection.
import Foundation
import Core

public struct NamedServiceAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let serviceName: String?
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?

    public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("share"),
        serviceName: String? = nil,
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.serviceName = serviceName
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
        return .showServices(context.selection.text)
    }
}