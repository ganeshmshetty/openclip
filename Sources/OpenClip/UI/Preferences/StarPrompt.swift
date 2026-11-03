// StarPrompt.swift
// OpenClip
//
// The one-time "star the repo" ask. It renders inside the Settings window — a centred dialog over a
// scrim, so nothing floats outside the app — and retires itself for good once answered or dismissed.

import SwiftUI
import AppKit
import Core

@MainActor
final class StarPrompt: ObservableObject {
    static let shared = StarPrompt()

    static let repositoryURL = URL(string: "https://github.com/ganeshmshetty/openclip")!
    static let minimumAge: TimeInterval = 7 * 24 * 60 * 60

    private let settingsStore: any SettingsStore
    private let now: () -> Date

    @Published private(set) var isVisible = false

    init(settingsStore: any SettingsStore = DefaultSettingsStore.shared,
         now: @escaping () -> Date = Date.init) {
        self.settingsStore = settingsStore
        self.now = now
    }

    /// Whether the ask is due. Installs that predate `onboardingCompletedAt` are stamped here and
    /// wait their week from the update, so nobody gets asked the day they update. Touches no UI,
    /// which is what the tests drive.
    func evaluate() -> Bool {
        guard !settingsStore.get(.hasDismissedStarPrompt) else { return false }

        let current = now().timeIntervalSince1970
        let completedAt = settingsStore.get(.onboardingCompletedAt)
        guard completedAt > 0 else {
            settingsStore.set(.onboardingCompletedAt, value: current)
            return false
        }
        guard current - completedAt >= Self.minimumAge else { return false }
        guard settingsStore.get(.pauseUntilTimestamp) <= current else { return false }

        return true
    }

    /// Called on every Settings open.
    func present() {
        guard evaluate() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = true
        }
    }

    func openRepository() {
        NSWorkspace.shared.open(Self.repositoryURL)
        dismiss()
    }

    func dismiss() {
        settingsStore.set(.hasDismissedStarPrompt, value: true)
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = false
        }
    }

    /// Closing Settings with the ask still up counts as a no, so it never comes back.
    func dismissIfShowing() {
        guard isVisible else { return }
        dismiss()
    }
}

/// Centred over the whole window, on a scrim, the way a modal panel reads on macOS.
@MainActor
struct StarPromptOverlay: View {
    let onStar: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())

            VStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                Text(String(localized: "Finding OpenClip useful?"))
                    .font(.system(size: 15, weight: .semibold))

                Text(String(localized: "It's free and open source. A star on GitHub helps more people find it."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)

                HStack(spacing: 10) {
                    Button(String(localized: "Not Now"), action: onDismiss)
                        .controlSize(.large)
                    Button(String(localized: "Star on GitHub"), action: onStar)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(width: 360)
            .settingsGlassCard(cornerRadius: 16)
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss"))
                .accessibilityLabel(String(localized: "Dismiss"))
                .padding(8)
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}
