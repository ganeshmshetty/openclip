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
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.38)
    }

    public var body: some View {
        ZStack {
            shape.fill(.regularMaterial)
            shape.fill(scrimColor)
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
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.28), Color.white.opacity(0.10)]
                : [Color.black.opacity(0.16), Color.black.opacity(0.06)],
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
    /// Renders a layered frosted glass surface with backing scrim, regular material, and specular stroke.
    func layeredGlassSurface(
        cornerRadius: CGFloat = 14,
        colorScheme: ColorScheme
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: colorScheme))
            .clipShape(shape)
            .overlay(LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: colorScheme))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 6, x: 0, y: 3)
    }

    /// Renders the view as a glass surface using regular material for a frosted look.
    func glassSurface(
        _ variant: LiquidGlassVariant = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
