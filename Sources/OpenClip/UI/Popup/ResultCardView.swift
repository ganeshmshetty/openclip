// ResultCardView.swift
// OpenClip
//
// The native result card rendered in content mode in place of the bar: a header (back chevron,
// producing action's icon or sparkles + title), a scrollable response body (error-styled when the
// action failed), and a Copy/Paste footer (hidden on error; Paste hidden when the target app can't
// paste). Any action whose resolved outcome is text renders here, not just AI presets.
// Paste/Copy are explicit user requests routed through performCardEffect, so an explicit Paste
// always pastes, and both dismiss the popup (Copy like Paste). The panel is key while the card
// shows (Task 14) and the card owns the keys (SwiftUI .onKeyPress): Esc collapses, Return pastes,
// Shift+Return copies — the controller-level key monitor stays observation-only in content mode.
import SwiftUI

// MARK: - Effective Theme Injection

/// Carries the popup's resolved theme token ("light"/"dark"/"glass") down to the card so its
/// chrome matches the bar (PopupView sets both this and the forced `.colorScheme`).
private struct PopupEffectiveThemeKey: EnvironmentKey {
    static let defaultValue = "dark"
}

extension EnvironmentValues {
    var popupEffectiveTheme: String {
        get { self[PopupEffectiveThemeKey.self] }
        set { self[PopupEffectiveThemeKey.self] = newValue }
    }
}

// MARK: - Result Card

public struct ResultCardView: View {
    public let payload: ResultCardPayload
    /// Paste availability of the target app (from the AX probe); `false` hides the Paste button.
    public let canPaste: Bool?
    public let onExit: @MainActor () -> Void
    public let onPaste: @MainActor () -> Void
    public let onCopy: @MainActor () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var effectiveTheme
    @FocusState private var isCardFocused: Bool
    @State private var isChevronHovered = false

    public init(
        payload: ResultCardPayload,
        canPaste: Bool? = nil,
        onExit: @escaping @MainActor () -> Void,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void
    ) {
        self.payload = payload
        self.canPaste = canPaste
        self.onExit = onExit
        self.onPaste = onPaste
        self.onCopy = onCopy
    }

    public var body: some View {
        cardChrome {
            VStack(spacing: 0) {
                header
                bodyScroll
                if !payload.isError {
                    footer
                }
            }
        }
        .frame(minWidth: PopupMetrics.aiCardMinWidth,
               idealWidth: PopupMetrics.aiCardIdealWidth,
               maxWidth: PopupMetrics.aiCardMaxWidth)
        .focusable()
        .focusEffectDisabled()
        .focused($isCardFocused)
        .onAppear {
            isCardFocused = true
        }
        .onKeyPress(.escape) {
            onExit()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            // Return pastes (an explicit request, so it always pastes); Shift+Return copies.
            // When the target can't paste the button is hidden, so Return falls back to copy.
            if press.modifiers.contains(.shift) || canPaste == false {
                onCopy()
            } else {
                onPaste()
            }
            return .handled
        }
    }

    // MARK: Chrome

    private func cardChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PopupMetrics.popupCornerRadius, style: .continuous)
        let borderColor: Color = colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
        return content()
            .background(
                effectiveTheme == "glass"
                    ? AnyShapeStyle(.ultraThinMaterial)
                    : AnyShapeStyle(
                        Color(red: colorScheme == .dark ? 0.20 : 0.91,
                              green: colorScheme == .dark ? 0.20 : 0.91,
                              blue: colorScheme == .dark ? 0.22 : 0.93)
                    )
            )
            .clipShape(shape)
            .overlay(shape.stroke(borderColor, lineWidth: 1.0))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 6, x: 0, y: 3)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onExit()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isChevronHovered ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                    .frame(width: 26, height: 26)
                    .background(
                        isChevronHovered ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to actions")
            .accessibilityLabel("Back to actions")
            .onHover { isChevronHovered = $0 }

            if payload.isStreaming {
                ProgressView()
                    .controlSize(.small)
            } else if let icon = payload.icon {
                // The producing action's own icon (bar-resolution: honors user overrides),
                // so extension results keep their identity in the card.
                ActionIconView(icon: icon, size: 12)
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            Text(payload.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle().fill(PopupThemeModel.dividerColor(for: effectiveTheme))
                .frame(height: 0.6),
            alignment: .bottom
        )
    }

    // MARK: Body

    private var bodyScroll: some View {
        ScrollView {
            Text(payload.text)
                .font(.system(size: 13))
                .foregroundColor(payload.isError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(height: PopupMetrics.aiCardBodyHeight)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                onCopy()
            } label: {
                HStack(spacing: 3) {
                    Text("Copy")
                    Image(systemName: "shift")
                    Image(systemName: "return")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PopupThemeModel.dividerColor(for: effectiveTheme), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Copy the response to the clipboard and close (⇧⏎)")
            .accessibilityLabel("Copy response and close")

            if canPaste != false {
                Button {
                    onPaste()
                } label: {
                    Label("Paste", systemImage: "return")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Paste the response over the selection (⏎)")
                .accessibilityLabel("Paste response over selection")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle().fill(PopupThemeModel.dividerColor(for: effectiveTheme))
                .frame(height: 0.6),
            alignment: .top
        )
    }
}