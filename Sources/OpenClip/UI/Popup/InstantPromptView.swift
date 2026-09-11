// InstantPromptView.swift
// OpenClip
//
// The Instant AI prompt: the smallest possible AI surface. The hotkey opens it at the selection —
// one field, no bar, no palette, no card — and ⏎ replaces the selection with AI's answer as soon
// as it lands (copies it when the target can't paste). ⇧⏎ is the review path: the answer streams
// into the normal result card instead. ↑ recalls the last instruction, so a prompt used over and
// over is two keys away. Esc closes. Hosted in the popup's search mode (a scoped palette whose
// parent `composesPrompt`), so key mode, field focus, placement and Esc are the palette's.
import SwiftUI
import AppKit
import Core

@MainActor
struct InstantPromptView: View {
    /// The last instruction run from here; ↑ recalls it. nil when none yet.
    let lastPrompt: String?
    /// Paste availability of the target app: `false` turns the ⏎ hint into "copy result".
    let canPaste: Bool?
    /// Runs the instruction. `replace` is true for ⏎ (paste over the selection), false for ⇧⏎
    /// (show the result card).
    let onRun: @MainActor (String, Bool) -> Void
    /// Esc / the esc button.
    let onExit: @MainActor () -> Void

    @State private var query = ""
    @State private var isEscHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var effectiveTheme

    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 6) {
            fieldRow
            hintRow
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(width: Self.width)
        .popupCardChrome(cornerRadius: PopupMetrics.searchCornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme)
        .onAppear { isFocused = true }
    }

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
            TextField(String(localized: "Tell AI what to do with the selection…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .focused($isFocused)
                .onKeyPress { press in
                    switch press.key {
                    case .escape:
                        onExit()
                        return .handled
                    case .return:
                        run(replace: !press.modifiers.contains(.shift))
                        return .handled
                    case .upArrow:
                        guard let lastPrompt, !lastPrompt.isEmpty else { return .ignored }
                        query = lastPrompt
                        return .handled
                    default:
                        return .ignored
                    }
                }

            Button(action: onExit) {
                Text("esc")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(isEscHovered ? PopupThemeModel.restForeground(for: effectiveTheme) : PopupThemeModel.restSecondary(for: effectiveTheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(isEscHovered ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isEscHovered ? Color.primary.opacity(0.25) : Color.secondary.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .onHover { isEscHovered = $0 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06)))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 6, x: 0, y: 2.5)
    }

    /// What the keys do, in the order they matter.
    private var hintRow: some View {
        HStack(spacing: 10) {
            hint("⏎", canPaste == false ? String(localized: "copy result") : String(localized: "replace selection"))
            hint("⇧⏎", String(localized: "show result"))
            if let lastPrompt, !lastPrompt.isEmpty {
                hint("↑", String(localized: "last prompt"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 16)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.7))
            Text(label)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
        }
        .lineLimit(1)
    }

    private func run(replace: Bool) {
        let instruction = AIPromptText.instruction(from: query)
        guard !instruction.isEmpty else { return }
        onRun(instruction, replace)
    }
}
