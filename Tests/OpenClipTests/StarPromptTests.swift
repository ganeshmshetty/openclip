// StarPromptTests.swift
// OpenClipTests
//
// The one-time support window: the week after onboarding, established installs, pause, and the
// one-shot consumption.

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
        store.set(.onboardingCompletedAt, value: installedAt.timeIntervalSince1970)
    }

    private func makePrompt(daysAfterInstall: Double) -> StarPrompt {
        let now = installedAt.addingTimeInterval(daysAfterInstall * 86_400)
        return StarPrompt(settingsStore: store, now: { now })
    }

    func testStaysHiddenBeforeTheWeekIsUp() {
        XCTAssertFalse(makePrompt(daysAfterInstall: 6.9).isDue())
    }

    func testBecomesDueOnceTheWeekIsUp() {
        XCTAssertTrue(makePrompt(daysAfterInstall: 7).isDue())
    }

    func testEstablishedInstallIsDueImmediately() {
        XCTAssertTrue(makePrompt(daysAfterInstall: 400).isDue())
    }

    func testMissingOnboardingTimestampCountsAsEstablished() {
        store.set(.onboardingCompletedAt, value: 0)

        XCTAssertTrue(makePrompt(daysAfterInstall: 0).isDue())
    }

    func testSeenAskNeverReturns() {
        store.set(.hasSeenStarPrompt, value: true)

        XCTAssertFalse(makePrompt(daysAfterInstall: 400).isDue())
    }

    func testStaysHiddenWhilePaused() {
        store.set(.pauseUntilTimestamp, value: installedAt.addingTimeInterval(30 * 86_400).timeIntervalSince1970)

        XCTAssertFalse(makePrompt(daysAfterInstall: 7).isDue())
    }

    func testIgnoresInstallsThatNeverFinishedOnboarding() {
        store.set(.hasCompletedOnboarding, value: false)
        store.set(.onboardingCompletedAt, value: 0)

        XCTAssertFalse(makePrompt(daysAfterInstall: 400).isDue())
    }
}
