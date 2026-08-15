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

extension ActionDelivery {
    /// Manual equality: `ActionResult` deliberately does not conform to `Equatable` (plan
    /// constraint), so `secondary` is compared by pattern-matching the two values instead.
    /// Payloads that are themselves `Equatable` (String, URL, StatusFeedback, …) compare with `==`;
    /// unmatched case pairs and `.failure` are never equal.
    public static func == (lhs: ActionDelivery, rhs: ActionDelivery) -> Bool {
        lhs.primaryToast == rhs.primaryToast
            && lhs.secondaryToast == rhs.secondaryToast
            && areEqual(lhs.secondary, rhs.secondary)
    }

    private static func areEqual(_ a: ActionResult?, _ b: ActionResult?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            switch (lhs, rhs) {
            case (.success, .success), (.simulatePaste, .simulatePaste), (.none, .none):
                return true
            case (.copy(let x), .copy(let y)), (.cut(let x), .cut(let y)),
                 (.paste(let x), .paste(let y)), (.showServices(let x), .showServices(let y)),
                 (.copyDefinition(let x), .copyDefinition(let y)):
                return x == y
            case (.openURL(let x), .openURL(let y)):
                return x == y
            case (.showStatus(let x), .showStatus(let y)):
                return x == y
            case (.openConfiguration(let x), .openConfiguration(let y)):
                return x == y
            case (.shareService(let xi, let xt), .shareService(let yi, let yt)):
                return xi == yi && xt == yt
            case (.notify(let xt, let xb), .notify(let yt, let yb)):
                return xt == yt && xb == yb
            case (.keyPress(let x), .keyPress(let y)):
                return x == y
            case (.runShortcut(let xn, let xi), .runShortcut(let yn, let yi)):
                return xn == yn && xi == yi
            default:
                return false // includes .failure, .sequence — never equal without ActionResult ==
            }
        default:
            return false // nil vs non-nil
        }
    }
}
