// ActionDelivery.swift
// OpenClip
//
// Declares, per-action, how a secondary click and per-click toasts should behave. nil `secondary`
// means "derive from the primary result" (e.g. paste primary ⇒ copy); explicitly declaring an
// `ActionResult` opts in to a distinct secondary result. Extension actions and builtins opt in
// through `Action.delivery`; the presentation layer consumes it.
import Foundation

public struct ActionDelivery: Sendable, Equatable {
    public var secondary: ActionResult?
    public var primaryToast: StatusFeedback?
    public var secondaryToast: StatusFeedback?
    public init(secondary: ActionResult? = nil,
                primaryToast: StatusFeedback? = nil,
                secondaryToast: StatusFeedback? = nil) {
        self.secondary = secondary
        self.primaryToast = primaryToast
        self.secondaryToast = secondaryToast
    }
    public static var none: ActionDelivery { ActionDelivery() }
}
