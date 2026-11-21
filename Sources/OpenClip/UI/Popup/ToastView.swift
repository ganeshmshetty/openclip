// ToastView.swift
// OpenClip
//
// The one-line floating toast rendered by ToastPanelController: `[spinner | icon] message`,
// capped to a single line and themed through PopupThemeModel so it matches the bar.
import SwiftUI
import Core

struct ToastView: View {
    let feedback: StatusFeedback
    var onCancel: (() -> Void)? = nil
    var reservedWidth: CGFloat? = nil
    /// Pointer enter/leave; the controller holds the toast while hovered.
    var onHover: ((Bool) -> Void)? = nil

    @State private var isHovered = false

    @Setting(SettingKey.popupTheme) private var selectedTheme
    @Setting(SettingKey.popupThemeColor) private var themeColor
    @Setting(SettingKey.popupScale) private var popupScale
    @Environment(\.colorScheme) private var colorScheme

    init(feedback: StatusFeedback, onCancel: (() -> Void)? = nil,
         reservedWidth: CGFloat? = nil, onHover: ((Bool) -> Void)? = nil,
         settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.feedback = feedback
        self.onCancel = onCancel
        self.reservedWidth = reservedWidth
        self.onHover = onHover
        _selectedTheme = Setting(SettingKey.popupTheme, store: settingsStore)
        _themeColor = Setting(SettingKey.popupThemeColor, store: settingsStore)
        _popupScale = Setting(SettingKey.popupScale, store: settingsStore)
    }

    /// Same popup scale factor `PopupView` applies to the bar.
    private var scale: CGFloat { PopupMetrics.scaleMultiplier(for: popupScale) }

    private var cornerRadius: CGFloat { PopupMetrics.toastCornerRadius * scale }

    private var isGlass: Bool {
        PopupThemeModel.category(fromStored: selectedTheme) == .glass
    }

    private var effectiveTheme: String {
        if isGlass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var textColor: Color {
        switch feedback.style {
        case .error:
            return Color.red
        case .success, .info:
            return PopupThemeModel.restForeground(for: effectiveTheme)
        }
    }

    /// Flattens newlines and truncates with an ellipsis past `limit`.
    static func formatMessage(_ message: String, limit: Int = PopupMetrics.toastMaxCharacterLength) -> String {
        let singleLine = message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLine.count > limit else { return singleLine }
        guard limit > 1 else { return String(singleLine.prefix(limit)) }
        return String(singleLine.prefix(limit - 1)) + "…"
    }

    var body: some View {
        let isInteractive = feedback.isLoading && onCancel != nil
        let formattedMessage = Self.formatMessage(feedback.message)
        let isCancelHovered = isInteractive && isHovered
        let displayedMessage = isCancelHovered ? String(localized: "Cancel Task") : formattedMessage
        let activeForeground = textColor

        let content = HStack(spacing: 6 * scale) {
            if isCancelHovered {
                Image(systemName: "xmark")
                    .font(.system(size: 10 * scale, weight: .medium))
                    .frame(width: 16 * scale, height: 16 * scale)
            } else if feedback.isLoading {
                ToastSpinnerView(color: activeForeground, scale: scale)
            } else if let symbol = feedback.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundColor(feedback.style == .error ? Color.red : (feedback.style == .success ? Color.accentColor : activeForeground))
            }
            Text(displayedMessage)
                .font(.system(size: 11 * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(activeForeground)
        .padding(.horizontal, 11 * scale)
        .padding(.vertical, 5 * scale)
        .frame(minWidth: reservedWidth, alignment: isCancelHovered ? .center : .leading)
        .background {
            RoundedRectangle(cornerRadius: max(0, cornerRadius - 2 * scale), style: .continuous)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                .padding(2 * scale)
                .opacity(isCancelHovered ? 1 : 0)
                .allowsHitTesting(false)
        }

        Group {
            if isGlass {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                content
                    .background(
                        LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
                    )
                    .clipShape(shape)
                    .overlay(
                        LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
                    )
                    .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.25 : 0.15), radius: 4, x: 0, y: 1)
            } else {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                content
                    .background(
                        PopupThemeModel.classicSurfaceBackground(for: effectiveColorScheme, in: shape)
                    )
                    .clipShape(shape)
                    .overlay(
                        shape.stroke(
                            LinearGradient(
                                colors: effectiveColorScheme == .dark
                                    ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
                                    : [Color.black.opacity(0.18), Color.black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                    )
                    .overlay(
                        shape.inset(by: 0.5).stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(effectiveColorScheme == .dark ? 0.32 : 0.65),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                        .allowsHitTesting(false)
                    )
                    .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.28 : 0.12), radius: 4, x: 0, y: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            onHover?(hovering)
        }
        .onTapGesture {
            guard isInteractive else { return }
            onCancel?()
        }
        .environment(\.colorScheme, effectiveColorScheme)
    }
}

/// Custom spinner: AppKit-backed `ProgressView` ignores foreground color and tint on macOS.
private struct ToastSpinnerView: View {
    let color: Color
    let scale: CGFloat

    @State private var isSpinning = false

    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                RoundedRectangle(cornerRadius: 0.75 * scale, style: .continuous)
                    .fill(color)
                    .opacity(0.20 + 0.80 * (Double(i) / 7.0))
                    .frame(width: 1.5 * scale, height: 3.5 * scale)
                    .offset(y: -5.25 * scale)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .frame(width: 16 * scale, height: 16 * scale)
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
        .animation(isSpinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : nil, value: isSpinning)
        .onAppear {
            isSpinning = true
        }
        .onDisappear {
            isSpinning = false
        }
    }
}

