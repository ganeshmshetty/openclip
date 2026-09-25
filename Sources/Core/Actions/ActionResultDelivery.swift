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
//     default "Copied" toast fires for any copy outcome (`.copy`, `.copyContent`, `.copyDefinition`).
// Only paste outcomes are ever downgraded (`.paste`→`.copy`, `.pasteContent`→`.copyContent`); an
// explicit copy stays a copy, and non-text results (openURL, notify, keyPress, ...) pass through
// untouched. A top-level `.sequence` is resolved item by item; a declared secondary replaces the
// whole sequence once. Pure Core — no AppKit, no UserDefaults; `canPaste` is the injected,
// already-unified answer so this is unit-testable.
import Foundation

/// The user's chosen behavior when an action implicitly returns text (the General-tab setting,
/// "When an action returns text"). `.preview` renders the text in the AI result card;
/// `.paste`/`.copy` deliver it directly. Core never reads the setting itself — the controller
/// injects the per-click value into `resolve`.
public enum ResultDeliveryPreference: String, CaseIterable, Sendable, Equatable, Codable {
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

    /// The default companion toast when a result is delivered as a copy (or a
    /// `.copyDefinition` is delivered) and no toast is declared for the click.
    private static let copiedToast = StatusFeedback(message: String(localized: "Copied"), style: .success, symbolName: "checkmark")
    private static let copiedFileToast = StatusFeedback(message: String(localized: "Copied File"), style: .success, symbolName: "doc.on.doc")
    private static let savedFileToast = StatusFeedback(message: String(localized: "File Saved"), style: .success, symbolName: "arrow.down.circle")

    /// Decides the final ActionResult for a raw runtime outcome and the companion toast.
    ///
    /// The pipeline (Select → Probe → Toast):
    /// 1. **Select**: resolves the target delivery mode via User Override -> Author Recommendation ->
    ///    Output Kind default (`paste-or-copy` for text, `preview` for file). Applies author's
    ///    declared `delivery.secondary` if present; otherwise applies the Clipboard Invariant for
    ///    secondary clicks.
    /// 2. **Apply probe**: a chosen `.paste` is downgraded to `.copy` when `canPaste` is false.
    /// 3. **Toast**: `delivery.primaryToast` / `delivery.secondaryToast` per click, else the default
    ///    "Copied" / "Copied File" / "File Saved" toast for copy/save outcomes.
    ///
    /// - Parameters:
    ///   - raw: the result a runtime/effect produced (the action's primary outcome).
    ///   - clickIntent: how the user triggered the action.
    ///   - canPaste: the unified paste availability (rules + probe) for the target app.
    ///   - delivery: the action's declared secondary outcome and per-click toasts.
    ///   - preference: optional user per-action override.
    ///   - recommendedResult: optional author-declared delivery recommendation.
    ///   - outputKind: optional author-declared or inferred output kind.
    public static func resolve(
        raw: ActionResult,
        clickIntent: ClickIntent,
        canPaste: Bool,
        delivery: ActionDelivery = .none,
        preference: ResultDeliveryPreference? = nil,
        recommendedResult: ActionResultDeliveryMode? = nil,
        outputKind: ActionOutputKind? = nil
    ) -> (result: ActionResult, toast: StatusFeedback?) {
        let selected = select(
            raw: raw,
            clickIntent: clickIntent,
            delivery: delivery,
            preference: preference,
            recommendedResult: recommendedResult,
            outputKind: outputKind
        )
        let delivered = applyProbe(to: selected, canPaste: canPaste)
        let toast = toast(for: delivered, clickIntent: clickIntent, delivery: delivery)
        return (delivered, toast)
    }

    // MARK: - Decision pipeline

    /// Step 1 — Select: which result the delivery starts from.
    ///
    /// A declared secondary replaces the whole result once (including a top-level `.sequence`).
    /// Per-item rules then recurse into sequences via `selectItem`.
    public static func select(
        raw: ActionResult,
        clickIntent: ClickIntent,
        delivery: ActionDelivery,
        preference: ResultDeliveryPreference? = nil,
        recommendedResult: ActionResultDeliveryMode? = nil,
        outputKind: ActionOutputKind? = nil
    ) -> ActionResult {
        if clickIntent == .secondary, let declared = delivery.secondary {
            // Declared outcomes always win over automatic conventions.
            return declared
        }

        let explicitMode: ActionResultDeliveryMode?
        if let preference {
            switch preference {
            case .preview: explicitMode = .preview
            case .paste: explicitMode = .paste
            case .copy: explicitMode = .copy
            }
        } else if let recommendedResult {
            explicitMode = recommendedResult
        } else if let outputKind {
            switch outputKind {
            case .text: explicitMode = .pasteOrCopy
            case .file, .dynamic: explicitMode = .preview
            case .none: explicitMode = .preview
            }
        } else {
            explicitMode = nil
        }

        return selectItem(raw, clickIntent: clickIntent, explicitMode: explicitMode)
    }

    /// Per-item Select rules: recurses into `.sequence`, infers the delivery mode from the item
    /// when no override applies, and applies the Clipboard Invariant for secondary clicks. Has no
    /// declared-secondary check — that replaces the whole result once, before this walk.
    private static func selectItem(_ raw: ActionResult, clickIntent: ClickIntent, explicitMode: ActionResultDeliveryMode?) -> ActionResult {
        if case .sequence(let items) = raw {
            return .sequence(items.map { selectItem($0, clickIntent: clickIntent, explicitMode: explicitMode) })
        }

        let effectiveMode: ActionResultDeliveryMode
        if let explicitMode {
            effectiveMode = explicitMode
        } else if case .text = raw {
            effectiveMode = .pasteOrCopy
        } else if case .file = raw {
            effectiveMode = .preview
        } else {
            effectiveMode = .preview
        }

        if case .text(let text) = raw {
            if clickIntent == .primary {
                switch effectiveMode {
                case .preview:
                    return raw
                case .paste, .pasteOrCopy:
                    return .paste(text)
                case .copy:
                    return .copy(text)
                case .open, .save:
                    return .paste(text)
                }
            } else {
                // Secondary click on text: Clipboard Invariant
                switch effectiveMode {
                case .paste, .pasteOrCopy, .preview, .open, .save:
                    return .copy(text)
                case .copy:
                    // Primary copy -> Secondary preview
                    return .text(text)
                }
            }
        }

        if case .file(let payload) = raw {
            if clickIntent == .primary {
                switch effectiveMode {
                case .preview:
                    return raw
                case .save:
                    return .saveFile(payload.url)
                case .open:
                    return .openURL(payload.url)
                case .copy:
                    return .copyFile(payload.url)
                case .paste, .pasteOrCopy:
                    return raw
                }
            } else {
                // Secondary click on file: Clipboard Invariant
                switch effectiveMode {
                case .preview, .save, .open, .paste, .pasteOrCopy:
                    return .copyFile(payload.url)
                case .copy:
                    // Primary copy -> Secondary preview
                    return .file(payload)
                }
            }
        }

        if clickIntent == .secondary {
            if case .paste(let text) = raw {
                return .copy(text)
            }
            if case .pasteContent(let payload) = raw {
                return .copyContent(payload)
            }
            if case .file(let payload) = raw {
                return .copyFile(payload.url)
            }
        }
        return raw
    }

    /// Step 2 — Apply probe: a chosen `.paste`/`.pasteContent` is never delivered to a target that
    /// cannot paste. Single choke point for the paste→copy downgrade (plain and rich alike).
    /// Recurses into `.sequence` so wrapped pastes are probed too.
    private static func applyProbe(to selected: ActionResult, canPaste: Bool) -> ActionResult {
        switch selected {
        case .paste(let text):
            return canPaste ? .paste(text) : .copy(text)
        case .pasteContent(let payload):
            return canPaste ? .pasteContent(payload) : .copyContent(payload)
        case .sequence(let items):
            return .sequence(items.map { applyProbe(to: $0, canPaste: canPaste) })
        default:
            // `.copy`, `.copyContent`, `.cut`, and all non-text results are never downgraded.
            return selected
        }
    }

    /// Step 3 — Toast: the click's declared toast wins; the default "Copied" toast fires for any
    /// copy outcome (`.copy`, `.copyContent`, `.copyDefinition`) when no toast is declared.
    private static func toast(
        for delivered: ActionResult,
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
        if case .copyFile = delivered {
            return copiedFileToast
        }
        if case .saveFile = delivered {
            return savedFileToast
        }
        if deliveredIsCopyOutcome(delivered) {
            return copiedToast
        }
        return nil
    }

    private static func deliveredIsCopyOutcome(_ result: ActionResult) -> Bool {
        switch result {
        case .copy, .copyContent: return true
        default: return false
        }
    }
}
