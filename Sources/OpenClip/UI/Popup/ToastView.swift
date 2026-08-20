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
    @Environment(\.colorScheme) private var colorScheme

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
        let content = HStack(spacing: 6) {
            if feedback.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let symbol = feedback.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(feedback.style == .error ? Color.red : (feedback.style == .success ? Color.accentColor : textColor))
            }
            Text(feedback.message)
                .font(.system(size: 11, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)

        Group {
            if isGlass {
                if #available(macOS 26.0, *) {
                    content
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous))
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
                } else {
                    content
                        .background(
                            RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
                }
            } else {
                content
                    .background(opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous)
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.14 : 0.28), radius: 5, x: 0, y: 2)
            }
        }
        .environment(\.colorScheme, effectiveColorScheme)
    }
}
