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
public extension View {
    /// Renders the view as a Liquid Glass surface on macOS 26+, or an ultra-thin
    /// standard material on macOS 14-15 so the UI keeps a similar frosted look.
    func glassSurface(
        _ variant: LiquidGlassVariant = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                glassEffect(
                    variant == .regular ? .regular : .clear,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        }
    }
}
