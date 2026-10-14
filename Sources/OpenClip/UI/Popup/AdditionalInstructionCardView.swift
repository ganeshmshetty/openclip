// AdditionalInstructionCardView.swift
// OpenClip
//
// The card shown in `.instruction` mode, in place of the bar, before an AI preset that asks for a
// one-time additional instruction runs (`AIActionPreset.requestsAdditionalInstruction`). It has the
// result card's chrome: a header (the preset's icon and title, doubling as a drag handle, plus
// Close), a multiline editor, and a footer with Cancel and Run. The panel is key while the card
// shows, so the editor takes typing while the source app stays active and keeps its selection.
// ⏎ inserts a newline, ⌘⏎ runs, ⎋ cancels. Run is disabled while the field is blank and fires at
// most once; the controller additionally drops a submit for any request but the current one.
import SwiftUI
import Core

struct AdditionalInstructionCardView: View {
    let request: AdditionalInstructionRequest
    let onSubmit: @MainActor (String) -> Void
    let onCancel: @MainActor () -> Void
    var onDrag: @MainActor (ResultCardDragPhase) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var effectiveTheme
    @State private var instruction = ""
    @State private var didSubmit = false
    @State private var isDraggingCard = false
    @State private var isCloseHovered = false
    @State private var isCancelHovered = false
    @State private var isRunHovered = false

    /// Whether `text` may be submitted: anything but whitespace. Pure, for tests.
    static func canSubmit(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canRun: Bool { !didSubmit && Self.canSubmit(instruction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            editor
            footer
        }
        .frame(width: PopupMetrics.instructionCardWidth)
        .popupCardChrome(cornerRadius: PopupMetrics.cardCornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme)
        // Fallback for when the editor is not first responder (e.g. after clicking the header).
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func submit() {
        guard canRun else { return }
        didSubmit = true
        onSubmit(instruction)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                if let icon = request.icon, icon.symbolName != nil {
                    ActionIconView(icon: icon, size: 13)
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Text(request.preset.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(headerDragGesture)
            .help(String(localized: "Drag to move"))

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(isCloseHovered ? .primary : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.65))
                    .frame(width: 22, height: 22)
                    .popupHeaderButtonChrome(effectiveTheme: effectiveTheme, colorScheme: colorScheme, isHovered: isCloseHovered)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Cancel (⎋)"))
            .accessibilityLabel(String(localized: "Cancel"))
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(height: 40)
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                if !isDraggingCard {
                    isDraggingCard = true
                    onDrag(.began)
                }
                onDrag(.changed)
            }
            .onEnded { _ in
                guard isDraggingCard else { return }
                isDraggingCard = false
                onDrag(.ended)
            }
    }

    // MARK: - Editor

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: PopupMetrics.footerButtonCornerRadius, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        return MultilineTextEditor(
            text: $instruction,
            placeholder: String(localized: "Enter additional instructions..."),
            font: .systemFont(ofSize: 13),
            textInset: NSSize(width: 6, height: 7),
            accessibilityLabel: String(localized: "Additional instruction"),
            onCommandReturn: { submit() },
            onEscape: { onCancel() }
        )
        .frame(height: PopupMetrics.instructionEditorHeight)
        .background(
            shape
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
        )
        .clipShape(shape)
        .padding(.horizontal, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(String(localized: "⌘⏎ to run · ⎋ to cancel"))
                .font(.system(size: 11))
                .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                onCancel()
            } label: {
                Text(String(localized: "Cancel"))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .popupFooterButtonChrome(effectiveTheme: effectiveTheme, colorScheme: colorScheme, isHovered: isCancelHovered)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Cancel (⎋)"))
            .onHover { isCancelHovered = $0 }

            Button {
                submit()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Run"))
                        .font(.system(size: 11.5, weight: .medium))
                    Text("⌘⏎")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .popupFooterButtonChrome(effectiveTheme: effectiveTheme, colorScheme: colorScheme, isHovered: isRunHovered && canRun, tint: .accentColor)
                .opacity(canRun ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canRun)
            .help(String(localized: "Run with this instruction (⌘⏎)"))
            .accessibilityLabel(String(localized: "Run"))
            .onHover { isRunHovered = $0 }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}
