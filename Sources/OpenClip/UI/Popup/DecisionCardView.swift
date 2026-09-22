// DecisionCardView.swift
// OpenClip
//
// Compact Decision card: chips + confidence meter — never an AI prose card.
import SwiftUI
import Core

public struct DecisionCardView: View {
    public let presentation: DecisionPresentation
    public var onConfirm: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onPasteFiltered: ((String) -> Void)?

    public init(
        presentation: DecisionPresentation,
        onConfirm: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onPasteFiltered: ((String) -> Void)? = nil
    ) {
        self.presentation = presentation
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self.onPasteFiltered = onPasteFiltered
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: Constants.defaultDecisionIconSymbol)
                    .foregroundStyle(.tint)
                Text(presentation.toolTitle)
                    .font(.headline)
                Spacer()
                if let confidence = presentation.confidence {
                    ConfidenceMeter(value: confidence)
                }
            }

            FlowChips(chips: presentation.chips.isEmpty
                       ? presentation.answers.map(\.value.displayLabel)
                       : presentation.chips)

            if presentation.requiresConfirmation {
                Text("Low confidence — confirm before acting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let probs = presentation.answers.first?.probabilities, !probs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(probs.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.caption2)
                            Spacer()
                            Text(String(format: "%.0f%%", (probs[key] ?? 0) * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                if presentation.requiresConfirmation {
                    Button("Confirm") { onConfirm?() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if let paste = presentation.pastePayload, !paste.isEmpty {
                    Button("Paste filtered") { onPasteFiltered?(paste) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button("Dismiss") { onDismiss?() }
                    .buttonStyle(.plain)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ConfidenceMeter: View {
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: min(1, max(0, value)))
                .progressViewStyle(.linear)
                .frame(width: 64)
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(String(localized: "Confidence \(Int(value * 100)) percent"))
    }
}

struct FlowChips: View {
    let chips: [String]

    var body: some View {
        FlexibleChipWrap(chips: chips)
    }
}

/// Simple wrap layout for chips without external deps.
struct FlexibleChipWrap: View {
    let chips: [String]

    var body: some View {
        // LazyVGrid keeps Core-free UI simple on older macOS layouts.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
    }
}
