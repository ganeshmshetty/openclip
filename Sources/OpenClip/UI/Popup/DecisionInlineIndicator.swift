// DecisionInlineIndicator.swift
// OpenClip
//
// What a Decision tool shows in place of its icon while and after it runs: a spinner, then a tick or
// a cross for yes/no, a question mark when the model was not confident enough, the chosen label for
// a choice or score, or a warning when the provider failed. The outcome is deliberately quiet: in
// the sub-bar (`.bar`) the button takes a soft tint, in the palette (`.palette`) the whole row does,
// and the glyph is a plain symbol in a muted colour on top of it; the palette row appends a choice
// or score label as its trailing accessory. `PopupModeStore` clears the outcome after a few seconds.
import SwiftUI
import Core

/// Inline outcome of a Decision tool, kept per action id in `PopupModeStore.decisionStates`.
public enum DecisionInlineState: Equatable, Sendable {
    case running
    case yes
    case no
    /// Below the tool's confidence threshold, or no answer at all: a question mark.
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

    /// Soft wash behind a sub-bar button showing this outcome. `nil` while running so the button
    /// keeps its normal rest / hover look under the spinner.
    var barTint: Color? {
        switch self {
        case .running: return nil
        case .yes: return Color.green.opacity(0.16)
        case .no: return Color.red.opacity(0.16)
        case .unsure: return Color.gray.opacity(0.18)
        case .failed: return Color.orange.opacity(0.16)
        case .answer: return Color.accentColor.opacity(0.12)
        }
    }

    /// Glyph colour that reads on the tint without shouting: desaturated, mid-lightness so it works
    /// on both light and dark bars.
    var glyphColor: Color {
        switch self {
        case .yes, .answer: return Color(red: 0.20, green: 0.58, blue: 0.36)
        case .no: return Color(red: 0.78, green: 0.32, blue: 0.32)
        case .unsure: return Color.secondary
        case .failed: return Color(red: 0.84, green: 0.56, blue: 0.16)
        case .running: return Color.primary
        }
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
            glyph("checkmark", label: String(localized: "Yes"))
        case .no:
            glyph("xmark", label: String(localized: "No"))
        case .unsure:
            glyph("questionmark", label: String(localized: "Unsure"))
        case .failed:
            glyph("exclamationmark.triangle", label: String(localized: "Failed"))
        case .answer(let label):
            switch style {
            case .bar:
                Text(label)
                    .font(.system(size: 13 * scale, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foreground)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
            case .palette:
                glyph("checkmark", label: label)
            }
        }
    }

    private func glyph(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13 * scale, weight: .semibold))
            .foregroundStyle(state.glyphColor)
            .accessibilityLabel(label)
    }
}
