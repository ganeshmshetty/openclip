// DeliveryDecoratedAction.swift
// OpenClip
//
// Pure Core wrapper that stamps a declared `ActionDelivery` — a manifest `secondary`
// outcome plus per-click toasts — onto an existing action. It decoratively overrides
// only `delivery`: id/title/icon/chrome, enablement, and perform are all forwarded to
// the base action, so registry sorting, disabling, and customization that key off the
// action ID are unaffected. The factory wraps extension actions that declare
// secondary/toast/secondaryToast; non-declaring actions stay plain (delivery nil).
import Foundation

public struct DeliveryDecoratedAction: Action {
    public let base: any Action

    /// The declared delivery. Backed by a stored `ActionDelivery?` and exposed through a
    /// computed property so it witnesses the protocol's OPTIONAL `var delivery: ActionDelivery?`
    /// requirement — a non-optional stored `let delivery: ActionDelivery` would NOT witness it,
    /// and the extension default (nil) would win (Task 4 gotcha).
    public var delivery: ActionDelivery? { storedDelivery }
    private let storedDelivery: ActionDelivery?

    public init(
        base: any Action,
        delivery: ActionDelivery?
    ) {
        self.base = base
        self.storedDelivery = delivery
    }

    // MARK: - Action (forwarded to base)

    public var id: String { base.id }
    public var title: String { base.title }
    public var icon: ActionIcon { base.icon }
    public var chrome: ActionChrome { base.chrome }
    public var actionOptions: [ExtensionOption] { base.actionOptions }
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
}

extension DeliveryDecoratedAction: ConfigurableAction {
    public var preferenceIconName: String {
        (base as? any ConfigurableAction)?.preferenceIconName ?? Constants.defaultIconSymbol
    }
}
