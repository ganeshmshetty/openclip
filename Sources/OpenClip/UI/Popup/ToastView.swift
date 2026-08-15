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

    private var themeCategory: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: selectedTheme)
    }

    private var effectiveTheme: String {
        if themeCategory == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var bubbleFill: Color {
        switch effectiveTheme {
        case "light": return Color(red: 0.91, green: 0.91, blue: 0.93)
        case "dark": return Color(red: 0.20, green: 0.20, blue: 0.22)
        default: return Color(red: 0.15, green: 0.15, blue: 0.18)
        }
    }

    private var bubbleBorder: Color {
        effectiveTheme == "light" ? Color.black.opacity(0.20) : Color.white.opacity(0.22)
    }

    private var textColor: Color {
        switch feedback.style {
        case .success: return PopupThemeModel.restForeground(for: effectiveTheme)
        case .error: return .red
        case .info: return PopupThemeModel.restForeground(for: effectiveTheme)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if feedback.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let symbol = feedback.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(feedback.message)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous)
                .fill(bubbleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PopupMetrics.toastCornerRadius, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 5, x: 0, y: 2)
        .environment(\.colorScheme, PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark))
    }
}
