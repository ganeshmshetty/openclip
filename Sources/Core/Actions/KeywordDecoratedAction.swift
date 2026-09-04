// KeywordDecoratedAction.swift
// OpenClip
//
// Pure Core wrapper that stamps declared search keywords onto an existing action.
// It decoratively overrides `keywords`: id/title/icon/chrome, enablement, options, delivery,
// and perform are all forwarded to the base action.
import Foundation

public struct KeywordDecoratedAction: Action {
    public let base: any Action
    public let keywords: [String]

    public init(base: any Action, keywords: [String]) {
        self.base = base
        self.keywords = keywords
    }

    // MARK: - Action (forwarded to base)

    public var id: String { base.id }
    public var title: String { base.title }
    public var icon: ActionIcon { base.icon }
    public var chrome: ActionChrome { base.chrome }
    public var actionOptions: [ExtensionOption] { base.actionOptions }
    public var delivery: ActionDelivery? { base.delivery }

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
}

extension KeywordDecoratedAction: ConfigurableAction {
    public var preferenceIconName: String {
        (base as? any ConfigurableAction)?.preferenceIconName ?? Constants.defaultIconSymbol
    }
}
