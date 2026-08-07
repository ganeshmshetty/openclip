// ActionIdentity.swift
// OpenClip
//
// Canonical "loaded by" classification for an action, derived from its chrome metadata. Every UI
// surface (bar, palette, Preferences, onboarding) previously re-wrote `if case .X = action.chrome.*`
// heuristics; this is the single home so classification can't drift between surfaces. Pure Core —
// no AppKit/SwiftUI, no `switch action.id` string matching.
import Foundation

public enum ActionIdentity {
    /// True for first-party builtin rows (Copy/Cut/Search/… and the AI Tools launcher).
    public static func isBuiltin(_ action: any Action) -> Bool {
        if case .builtin = action.chrome.source { return true }
        return false
    }

    /// True for actions shipped by an installed extension package (matches on either the chrome
    /// source or the badge — both legacy carriers of the same fact).
    public static func isExtension(_ action: any Action) -> Bool {
        if case .extensionPkg = action.chrome.source { return true }
        if case .extensionPkg = action.chrome.badge { return true }
        return false
    }

    /// The extension package identifier for an extension-loaded action, if any.
    public static func extensionPackageID(of action: any Action) -> String? {
        if case .extensionPkg(let packageID) = action.chrome.source { return packageID }
        return nil
    }

    /// True for AI-preset actions (`.ai` source) — reachable via the palette and Preferences,
    /// never a popup bar row.
    public static func isAIPreset(_ action: any Action) -> Bool {
        if case .ai = action.chrome.source { return true }
        return false
    }

    /// True for the inline word-completion pseudo-action. It is registered in the catalog only so
    /// the popup can render its suggestions, and must never surface as a bar row or palette entry.
    public static func isCompletionPseudoAction(_ action: any Action) -> Bool {
        action.chrome.popupBehavior == .provideCompletions
    }
}
