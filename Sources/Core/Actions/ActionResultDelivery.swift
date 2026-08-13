// ActionResultDelivery.swift
// OpenClip
//
// The single, pure decision that standardizes how a text-producing result is delivered (paste vs
// copy). Per the standardized rule:
//   * a right-click or ⇧-click ALWAYS copies,
//   * an app that cannot paste (the unified `PasteAvailability` answer — per-app rules first, AX
//     probe fallback — says no) copies,
//   * otherwise the action's requested outcome (paste) is honored.
// Only `.paste` outcomes are ever downgraded to `.copy`; an explicit `.copy` stays a copy, and
// non-text results (openURL, notify, keyPress, ...) pass through untouched. Pure Core — no AppKit,
// no UserDefaults; `canPaste` is the injected, already-unified answer so this is unit-testable.
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
    ///   - canPaste: the unified paste availability (rules + probe) for the target app; callers
    ///     pre-resolve it via `PasteAvailability.effective`, treating unknown as cannot-paste.
    public static func resolve(
        raw: ActionResult,
        clickIntent: ClickIntent,
        canPaste: Bool
    ) -> ActionResult {
        guard case .paste(let text) = raw else {
            // `.copy`, `.cut`, and all non-text results are never downgraded.
            return raw
        }
        let forceCopy = (clickIntent == .forceCopy) || !canPaste
        return forceCopy ? .copy(text) : .paste(text)
    }
}
