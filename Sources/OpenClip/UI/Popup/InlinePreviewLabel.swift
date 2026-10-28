// InlinePreviewLabel.swift
// OpenClip
//
// One inline-preview line: optional symbol or emoji, optional color swatch, then the text.
import SwiftUI
import Core

struct InlinePreviewLabel: View {
    let preview: InlinePreview
    let fontSize: CGFloat
    let scale: CGFloat
    let foreground: Color

    var body: some View {
        HStack(spacing: PopupMetrics.inlinePreviewSpacing * scale) {
            if let icon = preview.icon {
                iconView(icon)
                    .accessibilityHidden(true)
            }
            if let color = preview.color {
                RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                    .fill(Self.fill(color))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
                    .frame(
                        width: PopupMetrics.inlineSwatchSide * scale,
                        height: PopupMetrics.inlineSwatchSide * scale
                    )
                    .accessibilityHidden(true)
            }
            Text(preview.text)
                .font(.system(size: fontSize * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(toneColor)
        }
    }

    @ViewBuilder
    private func iconView(_ icon: InlinePreviewIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: fontSize * scale, weight: .regular))
                .foregroundColor(toneColor)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: fontSize * scale))
        }
    }

    private var toneColor: Color {
        switch preview.tone {
        case .default:
            return foreground
        case .success:
            return Color(red: 0.18, green: 0.72, blue: 0.38)
        case .error:
            return Color(red: 0.90, green: 0.27, blue: 0.25)
        case .warning:
            return Color(red: 0.86, green: 0.62, blue: 0.10)
        }
    }

    private static func fill(_ color: InlinePreviewColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
