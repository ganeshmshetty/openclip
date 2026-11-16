// StarPrompt.swift
// OpenClip
//
// Schedules the one-time "support OpenClip" window. Eligibility is derived from onboarding
// completion: fresh installs wait a week, while an established install is already past that and
// sees the window on its first launch after updating. Once shown, it never returns.
import AppKit
import Core

@MainActor
final class StarPrompt {
    static let shared = StarPrompt()

    static let repositoryURL = URL(string: "https://github.com/ganeshmshetty/openclip")!
    static let supportURL = URL(string: "https://www.getopenclip.app/support")!
    static let minimumAge: TimeInterval = 7 * 24 * 60 * 60

    private let settingsStore: any SettingsStore
    private let now: () -> Date
    private var windowController: SupportPromptWindowController?

    init(
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.now = now
    }

    /// Seven days after onboarding completes. Installs that finished onboarding before the
    /// timestamp existed count as established and are due immediately.
    func isDue() -> Bool {
        guard !settingsStore.get(.hasSeenStarPrompt) else { return false }
        guard settingsStore.get(.hasCompletedOnboarding) else { return false }

        let current = now().timeIntervalSince1970
        guard settingsStore.get(.pauseUntilTimestamp) <= current else { return false }

        let completedAt = settingsStore.get(.onboardingCompletedAt)
        return completedAt <= 0 || current - completedAt >= Self.minimumAge
    }

    /// Presents when due. The ask is consumed here rather than on close, so quitting with the
    /// window open cannot show it again. `force` is the debug/demo path and does not consume it.
    func presentIfDue(force: Bool = false) {
        guard force || isDue() else { return }
        guard windowController == nil else { return }

        if !force {
            settingsStore.set(.hasSeenStarPrompt, value: true)
        }

        let controller = SupportPromptWindowController(
            onStar: { [weak self] in self?.open(Self.repositoryURL) },
            onSupport: { [weak self] in self?.open(Self.supportURL) },
            onClose: { [weak self] in self?.finish() }
        )
        windowController = controller
        AppActivationPolicy.enter()
        controller.showWindow(nil)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        finish()
    }

    private func finish() {
        windowController?.closeProgrammatically()
        windowController = nil
        AppActivationPolicy.leave()
    }
}
