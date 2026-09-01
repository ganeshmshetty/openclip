// ToastView.swift
// OpenClip
//
// The one-line floating toast rendered by ToastPanelController: `[spinner | icon] message`,
// capped to a single line and themed through PopupThemeModel so it matches the bar.
import SwiftUI
import Core

struct ToastView: View {
    let feedback: StatusFeedback

    @AppStorage(SettingKey.popupTheme.name) private var selectedTheme: String = SettingKey.popupTheme.defaultValue
    @AppStorage(SettingKey.popupThemeColor.name) private var themeColor: String = SettingKey.popupThemeColor.defaultValue
    @AppStorage(SettingKey.popupScale.name) private var popupScale: Int = SettingKey.popupScale.defaultValue
    @Environment(\.colorScheme) private var colorScheme

    /// Visual multiplier derived from the user's Popup Scale level (1...5) so the toast keeps pace
    /// with the popup bar it attaches to — same scale factor `PopupView` applies to the bar.
    private var scale: CGFloat { PopupMetrics.scaleMultiplier(for: popupScale) }

    /// Corner radius for the toast bubble, scaled with the popup scale.
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

    private var glassBorderColor: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    private var opaqueBackground: Color {
        effectiveTheme == "dark" ? Color(red: 0.20, green: 0.20, blue: 0.22) : Color(red: 0.91, green: 0.91, blue: 0.93)
    }

    private var opaqueBorder: Color {
        effectiveTheme == "light" ? Color.black.opacity(0.18) : Color.white.opacity(0.18)
    }

    private var textColor: Color {
        switch feedback.style {
        case .error:
            return Color.red
        case .success, .info:
            return PopupThemeModel.restForeground(for: effectiveTheme)
        }
    }

    var body: some View {
        let content = HStack(spacing: 6 * scale) {
            if feedback.isLoading {
                // macOS `.small` spinner is 16pt; scale its frame AND rendering so both the panel
                // sizing (hostingView.fittingSize) and the visible spinner track the popup scale.
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(scale)
                    .frame(width: 16 * scale, height: 16 * scale)
            } else if let symbol = feedback.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundColor(feedback.style == .error ? Color.red : (feedback.style == .success ? Color.accentColor : textColor))
            }
            Text(feedback.message)
                .font(.system(size: 11 * scale, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 11 * scale)
        .padding(.vertical, 5 * scale)

        Group {
            if isGlass {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(glassBorderColor, lineWidth: 1.0)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
            } else {
                content
                    .background(opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: Color.black.opacity(effectiveTheme == "light" ? 0.10 : 0.20), radius: 4, x: 0, y: 1)
            }
        }
        .environment(\.colorScheme, effectiveColorScheme)
    }
}
