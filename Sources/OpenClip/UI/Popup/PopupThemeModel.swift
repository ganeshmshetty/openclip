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

    /// The background fill for the classic (solid) popup surface.
    @ViewBuilder
    public static func classicSurfaceBackground(for colorScheme: ColorScheme, in shape: RoundedRectangle) -> some View {
        shape.fill(
            Color(
                red: colorScheme == .dark ? 0.15 : 0.94,
                green: colorScheme == .dark ? 0.15 : 0.94,
                blue: colorScheme == .dark ? 0.165 : 0.96
            )
        )
    }
}

// MARK: - Edge Fade

/// The fading layer that keeps the popup's fixed chrome — the search field, a card's header and
/// footer — legible over the rows scrolling beneath it.
///
/// A glass popup blurs and tints what scrolls under as a fading extension of the card material, so
/// the rows dissolve into a frosted edge instead of showing through a translucent band. A classic
/// popup fades its opaque card colour instead, since there is nothing behind it to blur.
struct PopupEdgeFade: View {
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge
    let effectiveTheme: String
    let colorScheme: ColorScheme
    let height: CGFloat
    /// The card's own colour: the tint blended over the blur for glass, the fill faded for classic.
    let cardColor: Color

    var body: some View {
        Group {
            if effectiveTheme == "glass" && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                LayeredGlassBackground(cornerRadius: 0, colorScheme: colorScheme)
                    .mask(fadeMask)
            } else {
                LinearGradient(stops: solidStops, startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    /// Opacity ramp: opaque at the pane's edge, clear away from it, so the blur dissolves rather
    /// than ending in a hard line.
    private var fadeMask: LinearGradient {
        switch edge {
        case .top:
            return LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black.opacity(0.9), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .bottom:
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.9), location: 0.5),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var solidStops: [Gradient.Stop] {
        switch edge {
        case .top:
            return [
                .init(color: cardColor, location: 0.0),
                .init(color: cardColor.opacity(0.85), location: 0.55),
                .init(color: cardColor.opacity(0.0), location: 1.0)
            ]
        case .bottom:
            return [
                .init(color: cardColor.opacity(0.0), location: 0.0),
                .init(color: cardColor.opacity(0.85), location: 0.45),
                .init(color: cardColor, location: 1.0)
            ]
        }
    }
}

// MARK: - Bottom Dissolve

/// Fades scroll content out into the card at the bottom edge by masking the content itself, rather
/// than painting a fade layer over it. The footer chrome sits on the card's own surface, so there is
/// no blur and no tint band at the bottom — rows simply lose opacity as they trail under the footer.
struct PopupBottomDissolve: ViewModifier {
    /// Height over which the content fades to clear.
    let height: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        )
    }
}

extension View {
    func popupBottomDissolve(height: CGFloat) -> some View {
        modifier(PopupBottomDissolve(height: height))
    }

    @ViewBuilder
    func paletteSafeAreaBar<Content: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *), !ProcessInfo.processInfo.arguments.contains("-XCTest") && NSClassFromString("XCTestCase") == nil {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing) {
                content()
                    .background(.ultraThinMaterial)
            }
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
        return content
            .background(
                Group {
                    if effectiveTheme == "glass" && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                        LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: colorScheme)
                    } else {
                        PopupThemeModel.classicSurfaceBackground(for: colorScheme, in: shape)
                    }
                }
            )
            .clipShape(shape)
            .overlay(outerBorder(shape))
            .overlay(rimHighlight(shape))
            // Edge-lit depth: a tight contact shadow grounds the card, a low-alpha ambient lifts
            // it. Geometry lives in `PopupMetrics` (`cardShadow*`) because `popupShadowInset` must
            // cover the ambient's full blur tail or the panel frame hard-clips it.
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.38 : 0.14),
                radius: PopupMetrics.cardShadowContactRadius,
                x: 0,
                y: PopupMetrics.cardShadowContactYOffset
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16),
                radius: PopupMetrics.cardShadowAmbientRadius,
                x: 0,
                y: PopupMetrics.cardShadowAmbientYOffset
            )
    }

    /// The outer hairline. Glass keeps its lit gradient; classic gets a top-to-bottom
    /// gradient that is slightly brighter at the top where ambient light hits.
    @ViewBuilder
    private func outerBorder(_ shape: RoundedRectangle) -> some View {
        if effectiveTheme == "glass" {
            LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: colorScheme)
        } else {
            shape.stroke(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
                        : [Color.black.opacity(0.16), Color.black.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.0
            )
        }
    }

    /// A 1px specular line just inside the top edge, fading out by the bottom: the highlight that
    /// makes the surface read as a lit pane rather than a flat slab. Inset so it never touches the
    /// outer hairline.
    private func rimHighlight(_ shape: RoundedRectangle) -> some View {
        shape.inset(by: 0.5).stroke(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.32 : 0.65),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1.0
        )
        .allowsHitTesting(false)
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

