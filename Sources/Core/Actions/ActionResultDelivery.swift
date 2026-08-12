// ActionResultDelivery.swift
// OpenClip
//
// The single, pure decision that standardizes how a text-producing result is delivered (paste vs
// copy). Per the standardized rule:
//   * a right-click or ⇧-click ALWAYS copies,
//   * an app that forbids paste (policy `denyPaste`) or cannot paste (probe says no) copies,
//   * otherwise the action's requested outcome (paste) is honored.
// Only `.paste` outcomes are ever downgraded to `.copy`; an explicit `.copy` stays a copy, and
// non-text results (openURL, notify, keyPress, ...) pass through untouched. Pure Core — no AppKit,
// no UserDefaults; `canPaste` and the app policy are injected inputs so this is unit-testable.
import Foundation

public enum ActionResultDelivery {
    /// How the user triggered the action — used to decide delivery. The popup populates this from
    /// the click that ran the action (right-click or a ⇧-modifier click maps to `.forceCopy`).
    public enum ClickIntent: Sendable, Equatable {
        case leftClick
        /// Right-click or a shift-click: always deliver as a copy.
        case forceCopy
    }

    /// Decides the final ActionResult for a raw runtime outcome.
    ///
    /// - Parameters:
    ///   - raw: the result a runtime/effect produced.
    ///   - clickIntent: how the user triggered the action.
    ///   - canPaste: whether the frontmost target app currently supports Paste (platform probe).
    ///   - policy: the source app's resolved policy; `denyPaste` forces a copy.
    public static func resolve(
        raw: ActionResult,
        clickIntent: ClickIntent,
        canPaste: Bool,
        policy: AppPolicyContext
    ) -> ActionResult {
        guard case .paste(let text) = raw else {
            // `.copy`, `.cut`, and all non-text results are never downgraded.
            return raw
        }
        let forceCopy = (clickIntent == .forceCopy) || policy.denyPaste || !canPaste
        return forceCopy ? .copy(text) : .paste(text)
    }
}
