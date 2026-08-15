// ActionResultDelivery.swift
// OpenClip
//
// The single, pure decision that standardizes how a text-producing result is delivered (paste vs
// copy) and which companion toast (if any) surfaces. The pipeline is Select → Probe → Toast:
//   * Select which result wins — a declared `delivery.secondary` for a secondary click, else the
//     primary `raw` (with the legacy default: a secondary click on a paste primary copies). The
//     declarative secondary is the declared *outcome* for static kinds/builtins; the JS imperative
//     branch (openclip.input.isSecondaryClick) is chosen in-script and simply arrives as `raw`.
//   * Apply probe — a `.paste` is never pasted into a target that cannot paste (the unified
//     `PasteAvailability` answer — per-app rules first, AX probe fallback — says no): it becomes
//     `.copy`.
//   * Toast — the click's declared toast (`primaryToast`/`secondaryToast`) wins; otherwise the
//     default "Copied" toast fires only when a paste context was delivered as a copy (derived or
//     declared) or when a `.copyDefinition` is delivered.
// Only `.paste` outcomes are ever downgraded to `.copy`; an explicit `.copy` stays a copy, and
// non-text results (openURL, notify, keyPress, ...) pass through untouched. Pure Core — no AppKit,
// no UserDefaults; `canPaste` is the injected, already-unified answer so this is unit-testable.
import Foundation

public enum ActionResultDelivery {
    /// How the user triggered the action — used to decide delivery. The popup populates this from
    /// the click that ran the action (right-click or a ⇧-modifier click maps to `.secondary`).
    public enum ClickIntent: Sendable, Equatable {
        case primary
        /// Right-click or a ⇧-modifier click maps to `.secondary`: the outcome requested by the
        /// click is always deliver as a copy.
        case secondary
    }

    /// The default companion toast when a paste context is delivered as a copy (or a
    /// `.copyDefinition` is delivered) and no toast is declared for the click.
    private static let copiedToast = StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark")

    /// Decides the final ActionResult for a raw runtime outcome and the companion toast.
    ///
    /// The pipeline (Select → Probe → Toast):
    /// 1. **Select**: a secondary click uses `delivery.secondary` when declared; otherwise the raw
    ///    result wins, except a secondary click on a `.paste` primary derives `.copy` (the legacy
    ///    default).
    /// 2. **Apply probe**: a chosen `.paste` is downgraded to `.copy` when `canPaste` is false.
    /// 3. **Toast**: `delivery.primaryToast` / `delivery.secondaryToast` per click, else the default
    ///    "Copied" toast when the pre-probe result was a paste context that delivered `.copy`
    ///    (either derived or declared), or when the delivered result is `.copyDefinition`; else nil.
    ///
    /// - Parameters:
    ///   - raw: the result a runtime/effect produced (the action's primary outcome).
    ///   - clickIntent: how the user triggered the action.
    ///   - canPaste: the unified paste availability (rules + probe) for the target app; callers
    ///     pre-resolve it via `PasteAvailability.effective`, treating unknown as cannot-paste.
    ///   - delivery: the action's declared secondary outcome and per-click toasts.
    public static func resolve(
        raw: ActionResult,
        clickIntent: ClickIntent,
        canPaste: Bool,
        delivery: ActionDelivery
    ) -> (result: ActionResult, toast: StatusFeedback?) {
        let selected = select(raw: raw, clickIntent: clickIntent, delivery: delivery)
        let delivered = applyProbe(to: selected, canPaste: canPaste)
        let toast = toast(for: raw, selected: selected, delivered: delivered, clickIntent: clickIntent, delivery: delivery)
        return (delivered, toast)
    }

    // MARK: - Decision pipeline

    /// Step 1 — Select: which result the delivery starts from.
    private static func select(raw: ActionResult, clickIntent: ClickIntent, delivery: ActionDelivery) -> ActionResult {
        if clickIntent == .secondary, let declared = delivery.secondary {
            return declared
        }
        if clickIntent == .secondary, case .paste(let text) = raw {
            // Legacy default: a secondary click on a paste primary copies.
            return .copy(text)
        }
        return raw
    }

    /// Step 2 — Apply probe: a chosen `.paste` is never delivered to a target that cannot paste.
    /// Single choke point for the `guard case .paste` downgrade.
    private static func applyProbe(to selected: ActionResult, canPaste: Bool) -> ActionResult {
        guard case .paste(let text) = selected else {
            // `.copy`, `.cut`, and all non-text results are never downgraded.
            return selected
        }
        return canPaste ? .paste(text) : .copy(text)
    }

    /// Step 3 — Toast: the click's declared toast wins; the default "Copied" toast fires only when
    /// a paste context was delivered as a copy (derived at select or downgraded by the probe) or a
    /// `.copyDefinition` is delivered.
    private static func toast(
        for raw: ActionResult,
        selected: ActionResult,
        delivered: ActionResult,
        clickIntent: ClickIntent,
        delivery: ActionDelivery
    ) -> StatusFeedback? {
        let declared = (clickIntent == .secondary) ? delivery.secondaryToast : delivery.primaryToast
        if let declared {
            return declared
        }
        if case .copyDefinition = delivered {
            return copiedToast
        }
        guard case .copy = delivered else { return nil }
        // The pre-probe result was a paste context (selected `.paste` downgraded by the probe, or a
        // paste primary derived/declared into `.copy` at select) that delivered `.copy`.
        if case .paste = selected { return copiedToast }
        if case .paste = raw { return copiedToast }
        return nil
    }
}
