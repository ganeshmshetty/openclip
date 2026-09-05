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
        .frame(width: dynamicCardWidth)
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
        let classicBorderColor: Color = colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
        return content()
            .background(
                Group {
                    if effectiveTheme == "glass" {
                        LayeredGlassBackground(cornerRadius: PopupMetrics.popupCornerRadius, colorScheme: colorScheme)
                    } else {
                        shape.fill(
                            Color(red: colorScheme == .dark ? 0.20 : 0.91,
                                  green: colorScheme == .dark ? 0.20 : 0.91,
                                  blue: colorScheme == .dark ? 0.22 : 0.93)
                        )
                    }
                }
            )
            .clipShape(shape)
            .overlay(
                Group {
                    if effectiveTheme == "glass" {
                        LayeredGlassBorder(cornerRadius: PopupMetrics.popupCornerRadius, colorScheme: colorScheme)
                    } else {
                        shape.stroke(classicBorderColor, lineWidth: 1.0)
                    }
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 6, x: 0, y: 3)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onExit()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isChevronHovered ? .accentColor : PopupThemeModel.restForeground(for: effectiveTheme).opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(
                        isChevronHovered ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to actions (Esc)")
            .accessibilityLabel("Back to actions")
            .onHover { isChevronHovered = $0 }

            if let icon = payload.icon {
                // The producing action's own icon (bar-resolution: honors user overrides),
                // so extension results keep their identity in the card.
                ActionIconView(icon: icon, size: 13)
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
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

    // MARK: Dynamic Dimensions

    private var dynamicCardWidth: CGFloat {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        let maxLineLength = lines.map(\.count).max() ?? trimmed.count
        let charCount = trimmed.count

        if maxLineLength <= 18 && charCount <= 30 {
            return PopupMetrics.aiCardMinWidth // 220
        } else if maxLineLength <= 35 && charCount <= 80 {
            return 260
        } else {
            return PopupMetrics.aiCardIdealWidth // 300
        }
    }

    private var dynamicBodyHeight: CGFloat {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        let lineCount = lines.count
        let charCount = trimmed.count

        if lineCount <= 1 && charCount <= 30 {
            return 72
        } else if lineCount <= 1 && charCount <= 60 {
            return 88
        } else if lineCount <= 2 && charCount <= 90 {
            return 104
        } else if lineCount <= 3 && charCount <= 140 {
            return 124
        } else if lineCount <= 4 && charCount <= 180 {
            return 144
        } else {
            return PopupMetrics.aiCardBodyHeight // 160 max height for scrolling
        }
    }

    // MARK: Body

    private var textTypography: (fontSize: CGFloat, fontWeight: Font.Weight, lineSpacing: CGFloat) {
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineCount = trimmed.components(separatedBy: .newlines).count
        let charCount = trimmed.count

        if charCount <= 30 && lineCount <= 1 {
            return (fontSize: 18, fontWeight: .medium, lineSpacing: 2)
        } else if charCount <= 80 && lineCount <= 2 {
            return (fontSize: 15.5, fontWeight: .medium, lineSpacing: 3)
        } else if charCount <= 160 && lineCount <= 4 {
            return (fontSize: 14, fontWeight: .regular, lineSpacing: 3)
        } else {
            return (fontSize: 13, fontWeight: .regular, lineSpacing: 3.5)
        }
    }

    private var bodyScroll: some View {
        let typography = textTypography
        let bodyHeight = dynamicBodyHeight
        return ScrollView {
            Text(payload.text)
                .font(.system(size: typography.fontSize, weight: typography.fontWeight))
                .lineSpacing(typography.lineSpacing)
                .multilineTextAlignment(.leading)
                .foregroundColor(payload.isError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(height: bodyHeight)
    }

    // MARK: Footer

    private var isCopyPrimary: Bool {
        canPaste == false
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                onCopy()
            } label: {
                HStack(spacing: 5) {
                    Text("Copy")
                    if isCopyPrimary {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.8)
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: "shift")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .opacity(0.6)
                    }
                }
                .font(.system(size: 12, weight: isCopyPrimary ? .semibold : .medium))
                .foregroundColor(isCopyPrimary ? .white : PopupThemeModel.restForeground(for: effectiveTheme))
                .padding(.horizontal, isCopyPrimary ? 12 : 10)
                .padding(.vertical, 5)
                .background(
                    isCopyPrimary ? Color.accentColor : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .help(isCopyPrimary ? String(localized: "Copy the response to the clipboard and close (⏎)") : String(localized: "Copy the response to the clipboard and close (⇧⏎)"))
            .accessibilityLabel("Copy response and close")

            if canPaste != false {
                Button {
                    onPaste()
                } label: {
                    HStack(spacing: 5) {
                        Text("Paste")
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.8)
                    }
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