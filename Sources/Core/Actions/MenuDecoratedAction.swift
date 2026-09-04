// MenuDecoratedAction.swift
// OpenClip
//
// Pure Core wrapper that stamps optional sub-menu behavior — a relevance regex — onto an existing
// action. It decoratively conforms the wrapped action to RelevanceProviding without changing its
// identity: id/title/icon/chrome, enablement, and perform are all forwarded to the base action, so
// registry sorting, disabling, and customization that key off the action ID are unaffected. The
// factory wraps extension actions that declare menuRelevance; non-declaring actions stay plain.
import Foundation

public struct MenuDecoratedAction: Action, RelevanceProviding {
    public let base: any Action
    public let menuRelevanceRegex: String?

    public init(
        base: any Action,
        menuRelevanceRegex: String? = nil
    ) {
        self.base = base
        self.menuRelevanceRegex = menuRelevanceRegex
    }

    // MARK: - Action (forwarded to base)

    public var id: String { base.id }
    public var title: String { base.title }
    public var icon: ActionIcon { base.icon }
    public var chrome: ActionChrome { base.chrome }
    public var actionOptions: [ExtensionOption] { base.actionOptions }

    /// Forwards any declared `ActionDelivery` from the base action so wrapping this
    /// decorator around a delivery-declaring action (e.g. DeliveryDecoratedAction) never
    /// shadows the declared delivery with the protocol's nil default.
    public var delivery: ActionDelivery? { base.delivery }
    public var keywords: [String] { base.keywords }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        base.isEnabled(for: context)
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        base.matchInfo(for: context)
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        try await base.perform(context)
    }

    // MARK: - RelevanceProviding

    /// Relevant unless a `menuRelevanceRegex` is present and the trimmed selection doesn't match.
    /// A malformed regex is treated as relevant (defensive, mirroring ActionVisibility), so a bad
    /// author pattern never hides a sub-action.
    public func isRelevant(for text: String) -> Bool {
        guard let regex = menuRelevanceRegex, !regex.isEmpty else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let pattern = try? NSRegularExpression(
                  pattern: regex,
                  options: [.dotMatchesLineSeparators, .caseInsensitive]
              ) else {
            return true
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return pattern.firstMatch(in: trimmed, options: [], range: range) != nil
    }
}

extension MenuDecoratedAction: ConfigurableAction {
    public var preferenceIconName: String {
        (base as? any ConfigurableAction)?.preferenceIconName ?? Constants.defaultIconSymbol
    }
}