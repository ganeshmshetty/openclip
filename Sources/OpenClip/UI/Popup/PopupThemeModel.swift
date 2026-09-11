// PopupThemeModel.swift
// OpenClip
//
// Pure resolution logic for the popup theme storage, shared by PopupView,
// ResultCardView and PopupThemeSelector. The theme has two axes: a category
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

// MARK: - Effective Theme Environment Key

/// Empty by default — "not set" — so a view hosted outside `PopupView` (previews, tests) falls
/// back to the shared `.primary`/`.secondary` tokens and stays readable under either color
/// scheme. A "dark" default painted white text onto a light card whenever the host forced a
/// light scheme without also setting this key. `PopupView` always sets it explicitly.
struct PopupEffectiveThemeKey: EnvironmentKey {
    static let defaultValue = ""
}

public extension EnvironmentValues {
    var popupEffectiveTheme: String {
        get { self[PopupEffectiveThemeKey.self] }
        set { self[PopupEffectiveThemeKey.self] = newValue }
    }
}

// MARK: - Shared Card Chrome

public struct PopupCardChromeModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let effectiveTheme: String
    public let colorScheme: ColorScheme

    public init(
        cornerRadius: CGFloat = PopupMetrics.cardCornerRadius,
        effectiveTheme: String,
        colorScheme: ColorScheme
    ) {
        self.cornerRadius = cornerRadius
        self.effectiveTheme = effectiveTheme
        self.colorScheme = colorScheme
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let classicBorderColor: Color = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        return content
            .background(
                Group {
                    if effectiveTheme == "glass" {
                        LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: colorScheme)
                    } else {
                        shape.fill(
                            Color(red: colorScheme == .dark ? 0.18 : 0.94,
                                  green: colorScheme == .dark ? 0.18 : 0.94,
                                  blue: colorScheme == .dark ? 0.20 : 0.96)
                        )
                    }
                }
            )
            .clipShape(shape)
            .overlay(
                Group {
                    if effectiveTheme == "glass" {
                        LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: colorScheme)
                    } else {
                        shape.stroke(classicBorderColor, lineWidth: 1.0)
                    }
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 10, x: 0, y: 4)
    }
}

public extension View {
    func popupCardChrome(
        cornerRadius: CGFloat = PopupMetrics.cardCornerRadius,
        effectiveTheme: String,
        colorScheme: ColorScheme
    ) -> some View {
        modifier(PopupCardChromeModifier(cornerRadius: cornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme))
    }
}

