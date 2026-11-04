// PopupThemeModel.swift
// OpenClip
//
// Pure resolution logic for popup theme storage, shared by PopupView, ResultCardView and
// PopupThemeSelector. Two axes: category ("classic" | "glass") and appearance ("system" | "light" | "dark").
//
// Storage:
//   "popupTheme": category. Legacy "system"/"light"/"dark" values mean classic.
//   "popupThemeColor": appearance, shared by both categories.
import SwiftUI

enum PopupThemeModel {
    enum Category: String {
        case classic
        case glass
    }

    /// Maps a stored `popupTheme` value to a category; legacy colour values mean classic.
    static func category(fromStored raw: String) -> Category {
        switch raw {
        case "glass", "classic":
            return raw == "glass" ? .glass : .classic
        default:
            return .classic
        }
    }

    static func classicToken(appearance: String, systemIsDark: Bool) -> String {
        if appearance == "system" { return systemIsDark ? "dark" : "light" }
        return appearance
    }

    /// Color scheme for the popup subtree so `.primary` and materials match the theme. Applied only
    /// inside the popup, so Preferences is unaffected.
    static func effectiveScheme(appearance: String, systemIsDark: Bool) -> ColorScheme {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return systemIsDark ? .dark : .light
        }
    }

    /// Resting foreground color. Glass follows `.primary` so it tracks the forced scheme.
    static func restForeground(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.85)
        case "dark": return .white.opacity(0.90)
        default: return .primary
        }
    }

    /// Slightly softened accent for the popup action bars.
    static var barHoverFill: Color {
        Color(nsColor: NSColor.controlAccentColor.blended(withFraction: 0.08, of: .white) ?? .controlAccentColor)
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

/// Fades the fixed chrome (search field, card header/footer) over scrolling rows. Glass blurs and
/// tints the fade; classic fades its opaque colour since there is nothing to blur.
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

    /// Opaque at the edge, clear away from it, so the blur dissolves without a hard line.
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

/// Fades scroll content into the card at the bottom by masking it. No blur or tint band: the footer
/// sits on the card surface.
struct PopupBottomDissolve: ViewModifier {
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

    /// Lays fixed chrome over the scroll view instead of insetting it: rows keep scrolling underneath,
    /// which is what lets the edge fade erase them there. The content margin keeps the first and last
    /// rows reachable.
    func paletteBar<Content: View>(
        edge: VerticalEdge,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        self
            .contentMargins(edge == .top ? .top : .bottom, height, for: .scrollContent)
            .overlay(alignment: edge == .top ? .top : .bottom) {
                content()
            }
    }

    /// Erases rows into the card over the last stretch inside each fixed bar, so content cross-fades
    /// instead of being cut at the bar edge. The mask is derived from the bar heights alone, so it
    /// never shifts while scrolling, and because it erases rather than paints, the bars and their
    /// controls are untouched. Inactive when the list cannot scroll.
    @ViewBuilder
    func paletteScrollFade(topInset: CGFloat, bottomInset: CGFloat, isActive: Bool) -> some View {
        Group {
            if isActive {
                mask { PaletteScrollFadeMask(topInset: topInset, bottomInset: bottomInset) }
            } else {
                self
            }
        }
        .paletteHidesSystemScrollEdge()
    }

    /// The system draws its own edge material where a scroll view meets a safe area, which over an
    /// opaque card is the band and hairline this fade replaces.
    @ViewBuilder
    fileprivate func paletteHidesSystemScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            self
                .scrollEdgeEffectHidden(true, for: .top)
                .scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
    }
}

private struct PaletteScrollFadeMask: View {
    let topInset: CGFloat
    let bottomInset: CGFloat
    /// Band width inside the bar: rows fade out before the bar's controls begin.
    private static let fade: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let topClear = clamp((topInset - Self.fade) / height)
            let topOpaque = max(topClear, clamp(topInset / height))
            let bottomOpaque = max(topOpaque, clamp(1 - bottomInset / height))
            let bottomClear = max(bottomOpaque, clamp(1 - (bottomInset - Self.fade) / height))

            LinearGradient(
                stops: [
                    .init(color: .clear, location: topClear),
                    .init(color: .black, location: topOpaque),
                    .init(color: .black, location: bottomOpaque),
                    .init(color: .clear, location: bottomClear)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

// MARK: - Effective Theme Environment Key

/// Empty ("not set") by default, so views hosted outside `PopupView` fall back to the shared
/// `.primary`/`.secondary` tokens. `PopupView` always sets it.
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

/// Shared footer control surface. Glass uses Liquid Glass on macOS 26+; classic keeps its tinted fill.
struct PopupFooterButtonChrome: ViewModifier {
    let effectiveTheme: String
    let colorScheme: ColorScheme
    let isHovered: Bool
    var tint: Color? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PopupMetrics.footerButtonCornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        Group {
            if effectiveTheme == "glass",
               #available(macOS 26.0, *),
               !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                if let tint {
                    content
                        .background(shape.fill(tint.opacity(colorScheme == .light ? 1.0 : (isHovered ? 0.38 : 0.28))))
                        .background(.ultraThinMaterial, in: shape)
                        .glassEffect(.regular.tint(tint.opacity(colorScheme == .light ? 1.0 : 0.42)).interactive(), in: shape)
                        .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.5))
                } else {
                    content
                        .background(shape.fill(Color.primary.opacity(isHovered ? 0.14 : 0.08)))
                        .background(.ultraThinMaterial, in: shape)
                        .glassEffect(.regular.interactive(), in: shape)
                        .overlay(
                            shape.stroke(
                                colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10),
                                lineWidth: 0.5
                            )
                        )
                }
            } else {
                content
                    .background(
                        shape.fill(
                        tint?.opacity(isHovered ? 0.85 : 1.0)
                            ?? Color.primary.opacity(isHovered
                                ? (colorScheme == .dark ? 0.18 : 0.12)
                                : (colorScheme == .dark ? 0.12 : 0.07))
                        )
                    )
                    .overlay(
                        shape.stroke(
                            tint == nil
                                ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                                : Color.white.opacity(0.20),
                            lineWidth: 0.5
                        )
                    )
            }
        }
    }
}

extension View {
    func popupFooterButtonChrome(
        effectiveTheme: String,
        colorScheme: ColorScheme,
        isHovered: Bool,
        tint: Color? = nil
    ) -> some View {
        modifier(
            PopupFooterButtonChrome(
                effectiveTheme: effectiveTheme,
                colorScheme: colorScheme,
                isHovered: isHovered,
                tint: tint
            )
        )
    }

    func popupHeaderButtonChrome(
        effectiveTheme: String,
        colorScheme: ColorScheme,
        isHovered: Bool,
        tint: Color? = nil
    ) -> some View {
        modifier(
            PopupHeaderButtonChrome(
                effectiveTheme: effectiveTheme,
                colorScheme: colorScheme,
                isHovered: isHovered,
                tint: tint
            )
        )
    }
}

/// Compact circular chrome for the result card's header controls.
private struct PopupHeaderButtonChrome: ViewModifier {
    let effectiveTheme: String
    let colorScheme: ColorScheme
    let isHovered: Bool
    var tint: Color? = nil

    private let shape = Circle()

    func body(content: Content) -> some View {
        Group {
            if effectiveTheme == "glass",
               #available(macOS 26.0, *),
               !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                if let tint {
                    content
                        .background(shape.fill(tint.opacity(isHovered ? 0.38 : 0.28)))
                        .background(.ultraThinMaterial, in: shape)
                        .glassEffect(.regular.tint(tint.opacity(0.42)).interactive(), in: shape)
                        .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.5))
                } else {
                    content
                        .background(shape.fill(Color.primary.opacity(isHovered ? 0.14 : 0.08)))
                        .background(.ultraThinMaterial, in: shape)
                        .glassEffect(.regular.interactive(), in: shape)
                        .overlay(
                            shape.stroke(
                                colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10),
                                lineWidth: 0.5
                            )
                        )
                }
            } else {
                content
                    .background(
                        shape.fill(
                            tint?.opacity(isHovered ? 0.85 : 1.0)
                                ?? Color.primary.opacity(isHovered
                                    ? (colorScheme == .dark ? 0.18 : 0.12)
                                    : (colorScheme == .dark ? 0.12 : 0.07))
                        )
                    )
                    .overlay(
                        shape.stroke(
                            tint == nil
                                ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                                : Color.white.opacity(0.20),
                            lineWidth: 0.5
                        )
                    )
            }
        }
    }
}

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

    @ViewBuilder
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if effectiveTheme == "glass" && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            shadowed(
                content
                    .background(LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: colorScheme))
                    .clipShape(shape)
                    .overlay(outerBorder(shape))
                    .overlay(rimHighlight(shape))
            )
        } else {
            content
                .clipShape(shape)
                .background {
                    // Rasterize only the surface and shadow. AppKit may promote live buttons to backing
                    // layers after presentation, and their clipping must not change the shadow buffer.
                    shadowed(PopupThemeModel.classicSurfaceBackground(for: colorScheme, in: shape))
                        .padding(PopupMetrics.popupShadowInset)
                        .drawingGroup()
                        .padding(-PopupMetrics.popupShadowInset)
                        .allowsHitTesting(false)
                }
                .overlay(outerBorder(shape))
                .overlay(rimHighlight(shape))
        }
    }

    private func shadowed<Surface: View>(_ surface: Surface) -> some View {
        surface
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

    /// Outer hairline; glass keeps its lit gradient, classic brightens at the top.
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

    /// 1px top highlight fading out by the bottom; inset so it never touches the hairline.
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

// MARK: - Action Bar Highlight

extension View {
    /// Search-style neutral highlight; inset chrome preserves the full button hit area.
    func popupBarHighlight(
        _ fill: Color,
        scale: CGFloat,
        isText: Bool = false,
        leadingEdge: Bool = false,
        trailingEdge: Bool = false,
        outerInset: CGFloat = 3,
        isHovered: Bool,
        namespace: Namespace.ID
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: (leadingEdge ? 10 : 7) * scale,
            bottomLeadingRadius: (leadingEdge ? 10 : 7) * scale,
            bottomTrailingRadius: (trailingEdge ? 10 : 7) * scale,
            topTrailingRadius: (trailingEdge ? 10 : 7) * scale,
            style: .continuous
        )
        return background {
            Group {
                if isHovered {
                    shape.fill(fill)
                        .matchedGeometryEffect(id: "barHover", in: namespace)
                } else {
                    shape.fill(fill)
                }
            }
            .padding(.leading, (leadingEdge ? outerInset : (isText ? 0 : 2)) * scale)
            .padding(.trailing, (trailingEdge ? outerInset : (isText ? 0 : 2)) * scale)
            .padding(.vertical, 3 * scale)
        }
    }
}
