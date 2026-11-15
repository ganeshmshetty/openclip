// StarPromptTests.swift
// OpenClipTests
//
// The one-time support window: the seven-day anchor, update installs, pause, and permanent dismissal.

import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class StarPromptTests: XCTestCase {
    private var store: MemorySettingsStore!
    private let installedAt = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        store = MemorySettingsStore()
        store.set(.hasCompletedOnboarding, value: true)
    }

    private func makePrompt(daysAfterInstall: Double) -> StarPrompt {
        let now = installedAt.addingTimeInterval(daysAfterInstall * 86_400)
        return StarPrompt(settingsStore: store, now: { now })
    }

    func testExistingInstallSchedulesOneWeekOut() {
        let prompt = makePrompt(daysAfterInstall: 0)
        prompt.scheduleIfNeeded()

        XCTAssertEqual(
            store.get(.starPromptEligibleAt),
            installedAt.addingTimeInterval(StarPrompt.minimumAge).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertFalse(prompt.isDue())
    }

    func testBecomesDueOnceTheWeekIsUp() {
        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()

        XCTAssertFalse(makePrompt(daysAfterInstall: 6.9).isDue())
        XCTAssertTrue(makePrompt(daysAfterInstall: 7).isDue())
    }

    func testLaterLaunchesDoNotMoveTheAnchor() {
        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()
        let anchor = store.get(.starPromptEligibleAt)

        makePrompt(daysAfterInstall: 3).scheduleIfNeeded()
        XCTAssertEqual(store.get(.starPromptEligibleAt), anchor, accuracy: 0.001)

        XCTAssertFalse(makePrompt(daysAfterInstall: 6.9).isDue())
        XCTAssertTrue(makePrompt(daysAfterInstall: 7).isDue())
    }

    func testDismissalIsPermanent() {
        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()
        let prompt = makePrompt(daysAfterInstall: 7)
        XCTAssertTrue(prompt.isDue())

        prompt.dismiss()

        XCTAssertTrue(store.get(.hasDismissedStarPrompt))
        XCTAssertFalse(makePrompt(daysAfterInstall: 400).isDue())
    }

    func testDismissedPromptNeverSchedules() {
        store.set(.hasDismissedStarPrompt, value: true)

        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()

        XCTAssertEqual(store.get(.starPromptEligibleAt), 0, accuracy: 0.001)
    }

    func testStaysHiddenWhilePaused() {
        store.set(.pauseUntilTimestamp, value: installedAt.addingTimeInterval(30 * 86_400).timeIntervalSince1970)
        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()

        XCTAssertFalse(makePrompt(daysAfterInstall: 7).isDue())
    }

    func testIgnoresInstallsThatNeverFinishedOnboarding() {
        store.set(.hasCompletedOnboarding, value: false)

        makePrompt(daysAfterInstall: 0).scheduleIfNeeded()

        XCTAssertEqual(store.get(.starPromptEligibleAt), 0, accuracy: 0.001)
        XCTAssertFalse(makePrompt(daysAfterInstall: 400).isDue())
    }

    func testOnboardingAnchorsTheWeekFromCompletion() {
        store.set(.starPromptEligibleAt, value: installedAt.addingTimeInterval(StarPrompt.minimumAge).timeIntervalSince1970)

        XCTAssertFalse(makePrompt(daysAfterInstall: 6.9).isDue())
        XCTAssertTrue(makePrompt(daysAfterInstall: 7).isDue())
    }
}
