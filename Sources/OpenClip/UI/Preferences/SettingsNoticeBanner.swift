// SettingsNoticeBanner.swift
// OpenClip
//
// The window's replacement for `NSAlert`: a message that floats at the top of the detail column,
// on a piece of Liquid Glass on macOS 26 and on a standard material before it. It says what went
// wrong where it went wrong, and it goes away with one click — or, when something destructive is
// about to happen, it asks first and waits for the red button.

import SwiftUI

@MainActor
struct SettingsNoticeBanner: View {
    let notice: SettingsNotice
    let onDismiss: () -> Void
    var onConfirm: (() -> Void)?

    private var symbol: String {
        switch notice.style {
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .destructiveConfirmation: return "trash.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch notice.style {
        case .info: return .accentColor
        case .error: return .orange
        case .destructiveConfirmation: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(symbolColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if notice.isConfirmation {
                // A question, so it gets the two buttons an alert would have had — and the
                // destructive one is never the default, so Return cannot go through with it.
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)

                Button(notice.confirmTitle ?? String(localized: "Continue")) {
                    onConfirm?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .settingsGlassCard(cornerRadius: 14)
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Liquid Glass where the system provides it, a frosted material where it does not. Reserved
    /// for the one surface here that floats over content — the notice — because glass belongs to
    /// the layer above content, not to content itself.
    @ViewBuilder
    func settingsGlassCard(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
