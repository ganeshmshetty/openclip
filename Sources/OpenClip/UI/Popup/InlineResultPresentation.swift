// InlineResultPresentation.swift
// OpenClip
//
// Shared native rendering and width measurement for typed inline results across the main bar,
// group sub-bar, and search palette. Host owns every visual: a bounded swatch slot and a
// single-line text preview.
import SwiftUI
import Core

@MainActor
enum InlineResultLayout {
    enum Surface {
        case bar
        case search

        var textFontSize: CGFloat {
            switch self {
            case .bar: return 15
            case .search: return 11
            }
        }

        var maxContentWidth: CGFloat {
            switch self {
            case .bar: return PopupMetrics.inlineResultMaxWidth
            case .search: return PopupMetrics.inlineSearchAccessoryMaxWidth
            }
        }

        var swatchSize: CGFloat {
            switch self {
            case .bar: return 14
            case .search: return 11
            }
        }
    }

    /// Per-character estimate, matching `PopupPageLayout`'s 15 pt baseline and the 11 pt search row.
    static func estimatedGlyphWidth(for surface: Surface, scale: CGFloat) -> CGFloat {
        switch surface {
        case .bar: return 9.0 * scale
        case .search: return 6.4 * scale
        }
    }

    static func estimatedWideGlyphWidth(for surface: Surface, scale: CGFloat) -> CGFloat {
        switch surface {
        case .bar: return 15.0 * scale
        case .search: return 11.0 * scale
        }
    }

    /// Intrinsic content width before the surface's max clamp. Rendering and packing share this.
    static func width(for value: InlineResultValue, surface: Surface, scale: CGFloat) -> CGFloat {
        switch value {
        case .text:
            let narrow = estimatedGlyphWidth(for: surface, scale: scale)
            let wide = estimatedWideGlyphWidth(for: surface, scale: scale)
            let intrinsic = value.displayText.reduce(CGFloat(0)) { total, character in
                total + (ActionTextIconStyle.rendersFullWidth(character) ? wide : narrow)
            }
            return min(intrinsic, surface.maxContentWidth * scale)
        case .color:
            // Inline surfaces show the swatch only; the full code stays in the card and accessibility label.
            return min(surface.swatchSize * scale, surface.maxContentWidth * scale)
        }
    }

    /// The accessibility/value presentation: full bounded text or the canonical hex.
    static func accessibilityValue(for value: InlineResultValue) -> String {
        value.rawValue
    }

    /// Announces the action title plus its typed value; display-only items say they are informational.
    static func accessibilityLabel(title: String, value: InlineResultValue, displayOnly: Bool) -> String {
        if displayOnly {
            return "\(title), \(String(localized: "Information")), \(value.rawValue)"
        }
        return "\(title): \(value.rawValue)"
    }
}

@MainActor
struct InlineResultLabel: View {
    let value: InlineResultValue
    let surface: InlineResultLayout.Surface
    let scale: CGFloat
    let foreground: Color

    var body: some View {
        switch value {
        case .text:
            Text(value.displayText)
                .font(.system(size: surface.textFontSize * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(foreground)
                .frame(maxWidth: InlineResultLayout.width(for: value, surface: surface, scale: scale),
                       alignment: .leading)
        case .color(let color):
            InlineColorSwatch(color: color, size: surface.swatchSize * scale)
                .frame(width: InlineResultLayout.width(for: value, surface: surface, scale: scale))
        }
    }
}

/// A color swatch with a checkerboard behind transparent colors and an outline for light/dark.@MainActor
struct InlineColorSwatch: View {
    let color: InlineColor
    let size: CGFloat

    private var fill: Color {
        Color(red: color.red, green: color.green, blue: color.blue).opacity(color.alpha)
    }

    var body: some View {
        ZStack {
            if color.alpha < 1 {
                Checkerboard()
            } else {
                Color(white: 0.93)
            }
            Rectangle().fill(fill)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.2), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(2, size * 0.2), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private struct Checkerboard: View {
        var body: some View {
            Canvas { context, canvasSize in
                let square = max(2, canvasSize.width / 4)
                let rows = Int(ceil(canvasSize.height / square))
                let columns = Int(ceil(canvasSize.width / square))
                for row in 0..<rows {
                    for column in 0..<columns where (row + column).isMultiple(of: 2) {
                        let rect = CGRect(
                            x: CGFloat(column) * square,
                            y: CGFloat(row) * square,
                            width: square,
                            height: square
                        )
                        context.fill(Path(rect), with: .color(Color(white: 0.78)))
                    }
                }
            }
            .background(Color(white: 0.93))
        }
    }
}

extension View {
    /// Applies a native hover tooltip only when the display-only detail is present.
    @ViewBuilder
    func helpIfPresent(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}
