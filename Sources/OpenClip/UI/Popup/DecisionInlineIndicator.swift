// DecisionInlineIndicator.swift
// OpenClip
//
// What a Decision tool shows in place of its icon while and after it runs: a spinner, then a green
// tick or a red cross for yes/no, a grey question mark when the model was not confident enough, the
// chosen label for a choice or score, or a warning when the provider failed. Drawn by the sub-bar (`.bar`, label text replaces the icon) and the palette
// (`.palette`, icon slot only; the row shows the label as its trailing accessory).
import SwiftUI
import Core

/// Inline outcome of a Decision tool, kept per action id in `PopupModeStore.decisionStates`.
public enum DecisionInlineState: Equatable, Sendable {
    case running
    case yes
    case no
    /// Below the tool's confidence threshold, or no answer at all: a grey question mark.
    case unsure
    /// A choice or score answer, already rendered as a short label.
    case answer(String)
    case failed

    /// The state for a finished decision: unsure below the confidence threshold, else the first
    /// answer decides the glyph.
    public init(_ presentation: DecisionPresentation) {
        guard let first = presentation.answers.first, !presentation.requiresConfirmation else {
            self = .unsure
            return
        }
        switch first.value {
        case .noul(let yes): self = yes ? .yes : .no
        case .choice, .score: self = .answer(first.value.displayLabel)
        }
    }

    /// The label a tick/cross-less surface should show, if any.
    public var label: String? {
        if case .answer(let text) = self { return text }
        return nil
    }
}

@MainActor
struct DecisionInlineIndicator: View {
    enum Style {
        case bar
        case palette
    }

    let state: DecisionInlineState
    let style: Style
    let foreground: Color
    let scale: CGFloat

    var body: some View {
        switch state {
        case .running:
            ToastSpinnerView(color: foreground, scale: scale)
                .accessibilityLabel(String(localized: "Deciding"))
        case .yes:
            glyph("checkmark.circle.fill", .green, String(localized: "Yes"))
        case .no:
            glyph("xmark.circle.fill", .red, String(localized: "No"))
        case .unsure:
            glyph("questionmark.circle.fill", .gray, String(localized: "Unsure"))
        case .failed:
            glyph("exclamationmark.triangle.fill", .orange, String(localized: "Failed"))
        case .answer(let label):
            switch style {
            case .bar:
                Text(label)
                    .font(.system(size: 13 * scale, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foreground)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
            case .palette:
                glyph("checkmark.circle.fill", .green, label)
            }
        }
    }

    private func glyph(_ name: String, _ color: Color, _ label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }
}
