// AIResultOverlayView.swift
// OpenClip
//
// Renders the overlay panel interface for displaying AI generation results with actions to copy or replace selection text.
import SwiftUI

@MainActor
public struct AIResultOverlayView: View {
    public let resultText: String
    public let isError: Bool
    public let onReplace: () -> Void
    public let onCopy: () -> Void
    public let onClose: () -> Void

    public init(
        resultText: String,
        isError: Bool = false,
        onReplace: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.resultText = resultText
        self.isError = isError
        self.onReplace = onReplace
        self.onCopy = onCopy
        self.onClose = onClose
    }

    @AppStorage("popupTheme") private var selectedTheme: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveTheme: String {
        if selectedTheme == "system" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return selectedTheme
    }

    private var cardBorder: Color {
        if isError {
            return Color.red.opacity(0.45)
        }
        return colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
    }

    public var body: some View {
        cardContainer
    }

    @ViewBuilder
    private var cardContainer: some View {
        let content = cardContent
            .padding(12)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

        if effectiveTheme == "glass" {
            if #available(macOS 26, *) {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
            }
        } else {
            let bgFill = effectiveTheme == "dark" ? Color(red: 0.20, green: 0.20, blue: 0.22) : Color(red: 0.98, green: 0.98, blue: 0.99)
            content
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bgFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1.0)
                )
                .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 10, x: 0, y: 4)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isError ? "AI Error" : "AI Result", systemImage: isError ? "exclamationmark.triangle" : "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isError ? .red : .accentColor)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(resultText)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(2)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 270)

            HStack(spacing: 8) {
                if !isError {
                    Button(action: onReplace) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(resultText.isEmpty)
                }

                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(resultText.isEmpty)
            }
        }
    }
}
