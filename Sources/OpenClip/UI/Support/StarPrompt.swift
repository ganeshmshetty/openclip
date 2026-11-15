// StarPrompt.swift
// OpenClip
//
// Schedules the one-time "support OpenClip" window: seven days after a fresh install's onboarding
// completes, or seven days after the first launch of the build that introduces it for existing
// installs. Once dismissed, it never returns.
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
    private var isForcedDemo = false

    init(
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.now = now
    }

    /// Called at launch. Installs that predate this window get their week from this first launch;
    /// a scheduled anchor is never moved by later updates.
    func scheduleIfNeeded() {
        guard !settingsStore.get(.hasDismissedStarPrompt) else { return }
        guard settingsStore.get(.hasCompletedOnboarding) else { return }
        guard settingsStore.get(.starPromptEligibleAt) <= 0 else { return }
        settingsStore.set(.starPromptEligibleAt, value: now().timeIntervalSince1970 + Self.minimumAge)
    }

    /// Whether the window may show now. Touches no UI, which is what the tests drive.
    func isDue() -> Bool {
        guard !settingsStore.get(.hasDismissedStarPrompt) else { return false }
        guard settingsStore.get(.hasCompletedOnboarding) else { return false }
        let current = now().timeIntervalSince1970
        let eligibleAt = settingsStore.get(.starPromptEligibleAt)
        guard eligibleAt > 0, current >= eligibleAt else { return false }
        guard settingsStore.get(.pauseUntilTimestamp) <= current else { return false }
        return true
    }

    /// Presents the window when due. `force` is the debug/demo path: it ignores the schedule and
    /// leaves dismissal unrecorded, so the real prompt still appears later.
    func presentIfDue(force: Bool = false) {
        guard force || isDue() else { return }
        guard windowController == nil else { return }
        isForcedDemo = force
        let controller = SupportPromptWindowController(
            onStar: { [weak self] in self?.open(Self.repositoryURL) },
            onSupport: { [weak self] in self?.open(Self.supportURL) },
            onClose: { [weak self] in self?.finish() }
        )
        windowController = controller
        AppActivationPolicy.enter()
        controller.showWindow(nil)
    }

    func dismiss() {
        finish()
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        finish()
    }

    private func finish() {
        if !isForcedDemo {
            settingsStore.set(.hasDismissedStarPrompt, value: true)
        }
        windowController?.closeProgrammatically()
        windowController = nil
        AppActivationPolicy.leave()
    }
}
