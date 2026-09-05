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

    @State private var isHovered = false

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
        let isInteractive = feedback.isLoading && onCancel != nil
        let displayedMessage = (isInteractive && isHovered) ? String(localized: "Cancel Task") : feedback.message
        let activeForeground: Color = (isInteractive && isHovered) ? .white : textColor

        let content = HStack(spacing: 6 * scale) {
            if feedback.isLoading {
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
        .frame(minWidth: reservedWidth, alignment: .leading)

        Group {
            if isGlass {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                content
                    .background(
                        Group {
                            if isInteractive && isHovered {
                                shape.fill(Color.accentColor)
                            } else {
                                LayeredGlassBackground(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
                            }
                        }
                    )
                    .clipShape(shape)
                    .overlay(
                        Group {
                            if isInteractive && isHovered {
                                shape.stroke(Color.accentColor, lineWidth: 1.0)
                            } else {
                                LayeredGlassBorder(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
                            }
                        }
                    )
                    .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.25 : 0.15), radius: 4, x: 0, y: 1)
            } else {
                content
                    .background((isInteractive && isHovered) ? Color.accentColor : opaqueBackground)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke((isInteractive && isHovered) ? Color.accentColor : opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: Color.black.opacity(effectiveTheme == "light" ? 0.10 : 0.20), radius: 4, x: 0, y: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            guard isInteractive else { return }
            isHovered = hovering
        }
        .onTapGesture {
            guard isInteractive else { return }
            onCancel?()
        }
        .environment(\.colorScheme, effectiveColorScheme)
    }
}

/// A smoothly rotating, color-adaptive spinner that respects foreground styling and scales with the popup.
/// Replaces AppKit-backed `ProgressView`, whose native CoreUI blades ignore `.foregroundColor`,
/// `.tint`, and `.colorMultiply` on macOS.
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
        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
        .onAppear {
            isSpinning = true
        }
    }
}

