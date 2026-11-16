// ActionIdentity.swift
// OpenClip
//
// Canonical action classification, derived from chrome metadata so every UI surface agrees.
import Foundation

public enum ActionIdentity {
    /// True for first-party builtin rows (Copy/Cut/Search/… and the AI Tools launcher).
    public static func isBuiltin(_ action: any Action) -> Bool {
        if case .builtin = action.chrome.source { return true }
        return false
    }

    /// True for actions shipped by an installed extension (chrome source or badge).
    public static func isExtension(_ action: any Action) -> Bool {
        if case .extensionPkg = action.chrome.source { return true }
        if case .extensionPkg = action.chrome.badge { return true }
        return false
    }

    /// The extension package identifier for an extension-loaded action, if any.
    public static func extensionPackageID(of action: any Action) -> String? {
        if case .extensionPkg(let packageID) = action.chrome.source { return packageID }
        if case .extensionPkg(let name) = action.chrome.badge { return name }
        return nil
    }

    /// The set of unique installed extension package IDs present in an action list.
    public static func installedPackageIDs(in actions: [any Action]) -> Set<String> {
        Set(actions.compactMap { extensionPackageID(of: $0) })
    }

    /// True for AI-preset actions (`.ai` source), grouped under AI Tools by default.
    public static func isAIPreset(_ action: any Action) -> Bool {
        if case .ai = action.chrome.source { return true }
        return false
    }

    /// The word-completion pseudo-action exists only to feed popup suggestions; never a row or palette entry.
    public static func isCompletionPseudoAction(_ action: any Action) -> Bool {
        action.chrome.popupBehavior == .provideCompletions
    }

    /// Ineligible: AI presets/launchers, the completion pseudo-action, and other groups (no nesting).
    public static func isEligibleForGrouping(_ action: any Action) -> Bool {
        !isAIPreset(action) &&
        !action.chrome.launchesAI &&
        action.id != "builtin.aiTools" &&
        !isCompletionPseudoAction(action) &&
        action.id != "builtin.completion" &&
        action.chrome.popupBehavior != .showSubActions &&
        action.chrome.rowStyle != .actionGroup &&
        !action.id.hasPrefix("vgroup.")
    }

    /// Leaf actions that actually run; containers and the AI Tools launcher are excluded.
    public static func isBindable(_ action: any Action) -> Bool {
        !action.chrome.launchesAI &&
        !action.chrome.displayOnly &&
        !isCompletionPseudoAction(action) &&
        action.chrome.popupBehavior != .showSubActions &&
        action.chrome.rowStyle != .actionGroup
    }

    /// Custom and extension actions can be duplicated; builtins and AI/completion entries cannot.
    public static func canDuplicate(_ action: any Action) -> Bool {
        if isAIPreset(action) || action.chrome.launchesAI || isCompletionPseudoAction(action) {
            return false
        }
        if isBuiltin(action) {
            return false
        }
        return true
    }
}
