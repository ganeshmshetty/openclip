// ActionResultDelivery.swift
// OpenClip
//
// The single, pure decision that standardizes how a text-producing result is delivered (paste vs
// copy) and which companion toast (if any) surfaces. The pipeline is Select → Probe → Toast:
//   * Select which result wins — a declared `delivery.secondary` for a secondary click, else the
//     primary `raw` (with the legacy default: a secondary click on a paste primary copies; the
//     rich analogue derives `.copyContent` from `.pasteContent`). The declarative secondary is the
//     declared *outcome* for static kinds/builtins; the JS imperative branch
//     (openclip.input.isSecondaryClick) is chosen in-script and simply arrives as `raw`.
//   * Apply probe — a `.paste`/`.pasteContent` is never pasted into a target that cannot paste
//     (the unified `PasteAvailability` answer — per-app rules first, AX probe fallback — says no):
//     it becomes `.copy`/`.copyContent`.
//   * Toast — the click's declared toast (`primaryToast`/`secondaryToast`) wins; otherwise the
//     default "Copied" toast fires only when a paste context was delivered as a copy (derived or
//     declared) or when a `.copyDefinition` is delivered.
// Only paste outcomes are ever downgraded (`.paste`→`.copy`, `.pasteContent`→`.copyContent`); an
// explicit copy stays a copy, and non-text results (openURL, notify, keyPress, ...) pass through
// untouched. Pure Core — no AppKit, no UserDefaults; `canPaste` is the injected, already-unified
// answer so this is unit-testable.
import Foundation

/// The user's chosen behavior when an action implicitly returns text (the General-tab setting,
/// "When an action returns text"). `.preview` renders the text in the AI result card;
/// `.paste`/`.copy` deliver it directly. Core never reads the setting itself — the controller
/// injects the per-click value into `resolve`.
public enum ResultDeliveryPreference: String, CaseIterable, Sendable, Equatable {
    case preview
    case paste
    case copy
}

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
    ///   - preference: the user's result delivery preference for implicitly returned text (`.text`).
    public static func resolve(
        raw: ActionResult,
        clickIntent: ClickIntent,
        canPaste: Bool,
        delivery: ActionDelivery,
        preference: ResultDeliveryPreference? = nil
    ) -> (result: ActionResult, toast: StatusFeedback?) {
        let selected = select(raw: raw, clickIntent: clickIntent, delivery: delivery, preference: preference)
        let delivered = applyProbe(to: selected, canPaste: canPaste)
        let toast = toast(for: raw, selected: selected, delivered: delivered, clickIntent: clickIntent, delivery: delivery)
        return (delivered, toast)
    }

    // MARK: - Decision pipeline

    /// Step 1 — Select: which result the delivery starts from.
    private static func select(raw: ActionResult, clickIntent: ClickIntent, delivery: ActionDelivery, preference: ResultDeliveryPreference?) -> ActionResult {
        if clickIntent == .secondary, let declared = delivery.secondary {
            // Declared outcomes always win over the picker.
            return declared
        }
        if case .text(let text) = raw {
            // Implicit returned text is governed by the user's per-click preference; nil → the
            // legacy default (primary pastes, secondary copies). `.preview` stays `.text` — a
            // presentation marker the controller renders in the AI result card, never delivered.
            let resolved = preference ?? (clickIntent == .secondary ? .copy : .paste)
            switch resolved {
            case .preview: return raw
            case .paste: return .paste(text)
            case .copy: return .copy(text)
            }
        }
        if clickIntent == .secondary, case .paste(let text) = raw {
            // Legacy default: a secondary click on a paste primary copies.
            return .copy(text)
        }
        if clickIntent == .secondary, case .pasteContent(let payload) = raw {
            // Rich analogue: a secondary click on a rich-paste primary copies the payload.
            return .copyContent(payload)
        }
        return raw
    }

    /// Step 2 — Apply probe: a chosen `.paste`/`.pasteContent` is never delivered to a target that
    /// cannot paste. Single choke point for the paste→copy downgrade (plain and rich alike).
    private static func applyProbe(to selected: ActionResult, canPaste: Bool) -> ActionResult {
        switch selected {
        case .paste(let text):
            return canPaste ? .paste(text) : .copy(text)
        case .pasteContent(let payload):
            return canPaste ? .pasteContent(payload) : .copyContent(payload)
        default:
            // `.copy`, `.copyContent`, `.cut`, and all non-text results are never downgraded.
            return selected
        }
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
        // A paste context delivered as a copy (plain or rich) shows the default "Copied".
        guard deliveredIsCopyOutcome(delivered) else { return nil }
        if wasPasteContext(selected) || wasPasteContext(raw) { return copiedToast }
        return nil
    }

    private static func deliveredIsCopyOutcome(_ result: ActionResult) -> Bool {
        switch result {
        case .copy, .copyContent: return true
        default: return false
        }
    }

    private static func wasPasteContext(_ result: ActionResult) -> Bool {
        switch result {
        case .paste, .pasteContent: return true
        default: return false
        }
    }
}
