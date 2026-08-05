// PopupThemeModel.swift
// OpenClip
//
// Pure resolution logic for the popup theme storage, shared by PopupView,
// BubbleCardView and PopupThemeSelector. The theme has two axes: a category
// ("classic" solid colors vs "glass" material) and a shared appearance
// ("system", "light" or "dark") that applies to whichever category is active.
//
// Storage:
//   "popupTheme"   — category: "classic" | "glass". Legacy stored
//                    values ("system"/"light"/"dark"/"glass") map onto
//                    this: colors → classic, "glass" → glass.
//   "popupThemeColor" — shared appearance: "system"/"light"/"dark",
//                    used by both Classic and Glass.
import SwiftUI

/// Resolves the popup theme storage into the tokens the rendering code switches on.
enum PopupThemeModel {
    enum Category: String {
        case classic
        case glass
    }

    /// Maps a stored `popupTheme` value to a category. Legacy values ("system"/"light"/"dark")
    /// mean the solid-color themes were active; "glass" means glass. New values pass through.
    static func category(fromStored raw: String) -> Category {
        switch raw {
        case "glass", "classic":
            return raw == "glass" ? .glass : .classic
        default:
            return .classic
        }
    }

    /// Resolves the classic appearance token ("light"/"dark"), honoring "system".
    static func classicToken(appearance: String, systemIsDark: Bool) -> String {
        if appearance == "system" { return systemIsDark ? "dark" : "light" }
        return appearance
    }

    /// The color scheme the popup subtree should render under so `.primary`/`.secondary` and
    /// materials match the effective theme — classic and glass alike. "system" follows the Mac;
    /// "light"/"dark" pin it regardless of the system. Applied only within the popup subtree so
    /// it never changes the surrounding Preferences window.
    static func effectiveScheme(appearance: String, systemIsDark: Bool) -> ColorScheme {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return systemIsDark ? .dark : .light
        }
    }

    /// The resting (non-hover) foreground color for content on the given effective theme
    /// token ("light"/"dark"/"glass"). Glass follows `.primary` so it tracks the forced scheme.
    static func restForeground(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.85)
        case "dark": return .white.opacity(0.90)
        default: return .primary
        }
    }

    /// The secondary foreground color (hints, badges) for the given effective theme token.
    static func restSecondary(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.55)
        case "dark": return .white.opacity(0.60)
        default: return .secondary
        }
    }

    /// The divider color between rows for the given effective theme token.
    static func dividerColor(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.12)
        case "dark": return .white.opacity(0.14)
        default: return .white.opacity(0.20)
        }
    }
}
