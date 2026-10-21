// ActionResultDelivery.swift
// OpenClip
//
// Pure decision for how a text or file result is delivered (paste vs copy) and which toast shows.
// Pipeline: Select (declared secondary, else user preference / recommendation / output-kind default,
// then the clipboard invariant on secondary clicks, except a user "Show in card" preference keeps
// text in the card) -> Probe (paste downgraded to copy when the target can't paste) -> Toast.
// Only paste outcomes are downgraded; non-text results pass through.
// Core stays free of AppKit and UserDefaults; `canPaste` is injected so this is unit-testable.
import Foundation

/// Behavior for an action that implicitly returns text. The controller injects the per-click value into `resolve`.
public enum ResultDeliveryPreference: String, CaseIterable, Sendable, Equatable, Codable {
    case preview
    case paste
    case copy
}

public enum ActionResultDelivery {
    public enum ClickIntent: Sendable, Equatable {
        case primary
        /// Right-click or ⇧-click. Copies, unless the primary outcome was already a copy or the user chose Show in card.
        case secondary
    }

    /// Default toast for copy outcomes when the click declares none.
    private static let copiedToast = StatusFeedback(message: String(localized: "Copied"), style: .success, symbolName: "checkmark")
    private static let copiedFileToast = StatusFeedback(message: String(localized: "Copied File"), style: .success, symbolName: "doc.on.doc")
    private static let savedFileToast = StatusFeedback(message: String(localized: "File Saved"), style: .success, symbolName: "arrow.down.circle")

    /// Final result and companion toast for a raw outcome. Pipeline details are in the file header.
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

    /// Step 1: a declared secondary replaces the whole result once; per-item rules then recurse into sequences.
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

        // A user who chose "Show in card" wants the card on every click: text results stay previews on
        // secondary clicks instead of falling back to copy. Recommendations and output-kind defaults don't count.
        let userChosePreview = preference == .preview
        return selectItem(raw, clickIntent: clickIntent, explicitMode: explicitMode, previewOnSecondary: userChosePreview)
    }

    /// Per-item select rules; recurses into `.sequence`. The declared secondary is handled before this walk.
    private static func selectItem(
        _ raw: ActionResult,
        clickIntent: ClickIntent,
        explicitMode: ActionResultDeliveryMode?,
        previewOnSecondary: Bool = false
    ) -> ActionResult {
        if case .sequence(let items) = raw {
            return .sequence(items.map {
                selectItem($0, clickIntent: clickIntent, explicitMode: explicitMode, previewOnSecondary: previewOnSecondary)
            })
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
                switch effectiveMode {
                case .preview where previewOnSecondary:
                    // User chose "Show in card": the secondary click shows the card too.
                    return raw
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

    /// Step 2: downgrades `.paste`/`.pasteContent` to copy when the target can't paste. The single choke point.
    private static func applyProbe(to selected: ActionResult, canPaste: Bool) -> ActionResult {
        switch selected {
        case .paste(let text):
            return canPaste ? .paste(text) : .copy(text)
        case .pasteContent(let payload):
            return canPaste ? .pasteContent(payload) : .copyContent(payload)
        case .sequence(let items):
            return .sequence(items.map { applyProbe(to: $0, canPaste: canPaste) })
        default:
            return selected
        }
    }

    /// Step 3: the click's declared toast wins; otherwise a default toast for copy and save outcomes.
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
        case .copy, .copyContent, .copySelection: return true
        default: return false
        }
    }
}
