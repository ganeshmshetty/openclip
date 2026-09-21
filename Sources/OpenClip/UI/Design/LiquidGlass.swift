// LiquidGlass.swift
// OpenClip
//
// Shared view modifiers for adopting Apple's Liquid Glass material on macOS 26+,
// with graceful standard-material fallbacks for macOS 14-15.
// Liquid Glass is a macOS 26 / iOS 26 material reserved for the navigation/functional
// layer (sidebars, toolbars, tab bars) that floats above content — see HIG "Materials".
// The regular variant adapts to what scrolls beneath it; the clear variant is only for
// media-rich backgrounds. Both variants need a dimming layer for legibility.
import SwiftUI
import AppKit

/// Chooses which Liquid Glass variant a surface uses.
public enum LiquidGlassVariant {
    /// Adaptive glass that maintains legibility over any content. Default.
    case regular
    /// Permanently more transparent; for media-rich backgrounds only.
    case clear
}

@MainActor
public struct LayeredGlassBackground: View {
    public let cornerRadius: CGFloat
    public let colorScheme: ColorScheme

    public init(cornerRadius: CGFloat = 14, colorScheme: ColorScheme) {
        self.cornerRadius = cornerRadius
        self.colorScheme = colorScheme
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.26)
    }

    public var body: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(scrimColor)
            }
        }
    }
}

public struct LayeredGlassBorder: View {
    public let cornerRadius: CGFloat
    public let colorScheme: ColorScheme

    public init(cornerRadius: CGFloat = 14, colorScheme: ColorScheme) {
        self.cornerRadius = cornerRadius
        self.colorScheme = colorScheme
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    public var strokeGradient: LinearGradient {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return LinearGradient(
                colors: [Color.primary.opacity(0.15), Color.primary.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.40),
                    Color.white.opacity(0.14),
                    Color.black.opacity(0.22)
                ]
                : [
                    Color.white.opacity(0.70),
                    Color.white.opacity(0.25),
                    Color.black.opacity(0.16)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var body: some View {
        shape.stroke(strokeGradient, lineWidth: 1.0)
    }
}

@MainActor
public extension View {
    /// Renders a layered frosted glass surface with backing scrim, liquid glass material, specular rim, and depth shadows.
    func layeredGlassSurface(
        cornerRadius: CGFloat = 14,
        colorScheme: ColorScheme
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: colorScheme))
            .clipShape(shape)
            .overlay(LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: colorScheme))
            .overlay(
                shape.inset(by: 0.5).stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.35 : 0.65),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
                .allowsHitTesting(false)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14),
                radius: PopupMetrics.cardShadowContactRadius,
                x: 0,
                y: PopupMetrics.cardShadowContactYOffset
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16),
                radius: PopupMetrics.cardShadowAmbientRadius,
                x: 0,
                y: PopupMetrics.cardShadowAmbientYOffset
            )
    }

    /// Renders the view as a glass surface using Liquid Glass on macOS 26+ or thin material for a frosted look, or solid background when Reduce Transparency is enabled.
    @ViewBuilder
    func glassSurface(
        _ variant: LiquidGlassVariant = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            background(
                Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            if #available(macOS 26.0, *) {
                self.glassEffect(variant == .clear ? .clear : .regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                background(
                    variant == .clear ? .ultraThinMaterial : .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        }
    }
}

/// A SwiftUI wrapper around AppKit's `NSVisualEffectView` for behind-window frosted glass, falling back to solid window background under Reduce Transparency.
@MainActor
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let solidView = NSView()
            solidView.wantsLayer = true
            solidView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return solidView
        }
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let ve = nsView as? NSVisualEffectView {
            ve.material = material
            ve.blendingMode = blendingMode
            ve.state = state
        } else {
            nsView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

