// ActionCapabilities.swift
// OpenClip
//
// Target-side capability facts and the single evaluator that turns them into visibility and
// delivery decisions. Core stays pure: the app gathers the evidence, this file decides.
import Foundation

/// Tri-state evidence about the target an action would act on. `unknown` is not `unavailable`:
/// each surface chooses whether a missing answer fails closed.
public enum CapabilityAvailability: String, Sendable, Equatable, Codable {
    case available
    case unavailable
    case unknown

    public init(_ confirmed: Bool?) {
        switch confirmed {
        case true: self = .available
        case false: self = .unavailable
        case nil: self = .unknown
        }
    }
}

/// What the frontmost target accepts right now.
public struct TargetCapabilities: Sendable, Equatable {
    /// The focused element accepts text insertion or replacement.
    public var textInsertion: CapabilityAvailability
    /// The target app advertises an enabled Paste command.
    public var pasteboardPaste: CapabilityAvailability
    /// The captured target is still frontmost with the same selection. Unknown until perform time.
    public var targetIsLive: CapabilityAvailability

    public init(
        textInsertion: CapabilityAvailability = .unknown,
        pasteboardPaste: CapabilityAvailability = .unknown,
        targetIsLive: CapabilityAvailability = .unknown
    ) {
        self.textInsertion = textInsertion
        self.pasteboardPaste = pasteboardPaste
        self.targetIsLive = targetIsLive
    }

    public static let unknown = TargetCapabilities()

    /// The per-app `denyPaste` rule is the explicit escape hatch for apps that advertise Paste but
    /// cannot reliably replace a selection. It forces every paste path to copy.
    public mutating func applyDenyPaste(_ policy: AppPolicyContext) {
        guard policy.denyPaste else { return }
        textInsertion = .unavailable
        pasteboardPaste = .unavailable
    }
}

/// What an action needs from its input and destination.
public enum ActionNeed: Sendable, Hashable {
    case text
    case liveSelection
    case editableText
    case pasteDestination
}

/// What a produced result needs in order to land.
public enum ActionEffectRequirement: Sendable, Equatable {
    case none
    case textInsertion
    case pasteboardPaste
}

public enum ActionEligibility {
    /// Declared manifest requirements, in evaluation order.
    public static func needs(for requirements: ActionRequirements?) -> [ActionNeed] {
        var needs: [ActionNeed] = []
        switch requirements?.input ?? .text {
        case .optional:
            break
        case .text:
            needs.append(.text)
        case .liveSelection:
            needs.append(contentsOf: [.text, .liveSelection])
        case .editableSelection:
            needs.append(contentsOf: [.text, .liveSelection, .editableText])
        }
        if requirements?.requiresPasteTarget == true {
            needs.append(.pasteDestination)
        }
        return needs
    }

    /// Strict requirement check: missing evidence fails. Used for declared requirements and for
    /// destructive effects, where a wrong guess is worse than hiding the action.
    public static func isSatisfied(
        requirements: ActionRequirements?,
        selection: SelectionContext?,
        capabilities: TargetCapabilities
    ) -> Bool {
        needs(for: requirements).allSatisfy {
            isSatisfied($0, selection: selection, capabilities: capabilities, unknownSatisfies: false)
        }
    }

    /// `unknownSatisfies` applies to the capability being asked about, never to liveness: a
    /// target that confirmed it went away always fails.
    public static func isSatisfied(
        _ need: ActionNeed,
        selection: SelectionContext?,
        capabilities: TargetCapabilities,
        unknownSatisfies: Bool
    ) -> Bool {
        switch need {
        case .text:
            guard let selection else { return false }
            return !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .liveSelection:
            return selection?.source == .selection && capabilities.targetIsLive != .unavailable
        case .editableText:
            return capabilities.targetIsLive != .unavailable
                && satisfies(capabilities.textInsertion, unknownSatisfies: unknownSatisfies)
        case .pasteDestination:
            return capabilities.targetIsLive != .unavailable
                && satisfies(capabilities.pasteboardPaste, unknownSatisfies: unknownSatisfies)
        }
    }

    public static func isSatisfied(
        _ needs: [ActionNeed],
        selection: SelectionContext?,
        capabilities: TargetCapabilities,
        unknownSatisfies: Bool
    ) -> Bool {
        needs.allSatisfy {
            isSatisfied($0, selection: selection, capabilities: capabilities, unknownSatisfies: unknownSatisfies)
        }
    }

    /// The strongest requirement a result carries. Sequences take the union of their items.
    public static func requirement(for result: ActionResult) -> ActionEffectRequirement {
        switch result {
        case .cut, .paste:
            return .textInsertion
        case .pasteContent(let payload):
            return payload.requiresTextInsertion ? .textInsertion : .pasteboardPaste
        case .simulatePaste:
            return .pasteboardPaste
        case .sequence(let items):
            return items.map(requirement(for:)).max(by: { rank($0) < rank($1) }) ?? .none
        default:
            return .none
        }
    }

    /// Delivery-time check. Missing evidence fails: only a confirmed destination receives a paste.
    public static func isDeliverable(
        _ requirement: ActionEffectRequirement,
        capabilities: TargetCapabilities
    ) -> Bool {
        guard capabilities.targetIsLive != .unavailable else { return false }
        switch requirement {
        case .none:
            return true
        case .textInsertion:
            return capabilities.textInsertion == .available
        case .pasteboardPaste:
            return capabilities.pasteboardPaste == .available
        }
    }

    /// Downgrades effects that cannot land into their non-destructive equivalents. A paste
    /// becomes a copy, and a cut becomes a copy so the text is never silently lost.
    public static func degrade(_ result: ActionResult, capabilities: TargetCapabilities) -> ActionResult {
        switch result {
        case .sequence(let items):
            return .sequence(items.map { degrade($0, capabilities: capabilities) })
        case .paste(let text), .cut(let text):
            return isDeliverable(.textInsertion, capabilities: capabilities) ? result : .copy(text)
        case .pasteContent(let payload):
            return isDeliverable(requirement(for: result), capabilities: capabilities)
                ? result
                : .copyContent(payload)
        case .simulatePaste:
            // Nothing to copy: the clipboard already holds the content. Only a confirmed
            // unavailable destination drops the keystroke; unknown keeps legacy behavior.
            return capabilities.pasteboardPaste == .unavailable || capabilities.targetIsLive == .unavailable
                ? .none
                : result
        default:
            return result
        }
    }

    private static func satisfies(_ availability: CapabilityAvailability, unknownSatisfies: Bool) -> Bool {
        switch availability {
        case .available: return true
        case .unavailable: return false
        case .unknown: return unknownSatisfies
        }
    }

    private static func rank(_ requirement: ActionEffectRequirement) -> Int {
        switch requirement {
        case .none: return 0
        case .textInsertion: return 1
        case .pasteboardPaste: return 2
        }
    }
}

public extension SelectionContext {
    /// Target-side view of the captured evidence. Liveness is supplied by the caller that knows
    /// whether the app is still frontmost and the selection unchanged.
    func targetCapabilities(targetIsLive: CapabilityAvailability = .unknown) -> TargetCapabilities {
        TargetCapabilities(
            textInsertion: CapabilityAvailability(isEditable),
            pasteboardPaste: CapabilityAvailability(pasteTargetAvailable),
            targetIsLive: targetIsLive
        )
    }
}

public extension ActionContext {
    var capabilities: TargetCapabilities {
        TargetCapabilities(
            textInsertion: CapabilityAvailability(selection.isEditable),
            pasteboardPaste: CapabilityAvailability(pasteTargetAvailable)
        )
    }
}

public extension RichPasteboardPayload {
    /// File and image payloads need a paste destination, not a text insertion point: Finder,
    /// Preview, and canvases accept them without an editable text control.
    var requiresTextInsertion: Bool {
        let fileTypes: Set<String> = ["public.file-url", "NSFilenamesPboardType"]
        if flavors.contains(where: { fileTypes.contains($0.type) }) { return false }
        if plainText != nil || html != nil || rtf != nil { return true }
        return flavors.contains { flavor in
            flavor.type.hasPrefix("public.utf") || flavor.type == "public.plain-text"
                || flavor.type == "public.rtf" || flavor.type == "public.html"
        }
    }
}
