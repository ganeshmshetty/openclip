// StarPromptTests.swift
// OpenClipTests
//
// The one-time star ask: age gate, pause, missing-timestamp stamping, and permanent dismissal.

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
        store.set(.onboardingCompletedAt, value: installedAt.timeIntervalSince1970)
    }

    private func makePrompt(daysAfterInstall: Double) -> StarPrompt {
        let now = installedAt.addingTimeInterval(daysAfterInstall * 86_400)
        return StarPrompt(settingsStore: store, now: { now })
    }

    func testStaysHiddenBeforeTheWeekIsUp() {
        XCTAssertFalse(makePrompt(daysAfterInstall: 6.9).evaluate())
    }

    func testAppearsOnceTheWeekIsUp() {
        XCTAssertTrue(makePrompt(daysAfterInstall: 7).evaluate())
    }

    func testDismissalIsPermanent() {
        let prompt = makePrompt(daysAfterInstall: 7)
        prompt.present()
        XCTAssertTrue(prompt.isVisible)

        prompt.dismiss()

        XCTAssertFalse(prompt.isVisible)
        XCTAssertTrue(store.get(.hasDismissedStarPrompt))
        XCTAssertFalse(makePrompt(daysAfterInstall: 400).evaluate())
    }

    func testClosingSettingsRetiresTheAsk() {
        let prompt = makePrompt(daysAfterInstall: 7)
        prompt.present()
        prompt.dismissIfShowing()

        XCTAssertTrue(store.get(.hasDismissedStarPrompt))
        XCTAssertFalse(makePrompt(daysAfterInstall: 400).evaluate())
    }

    func testStaysHiddenWhilePaused() {
        store.set(.pauseUntilTimestamp, value: installedAt.addingTimeInterval(30 * 86_400).timeIntervalSince1970)
        XCTAssertFalse(makePrompt(daysAfterInstall: 7).evaluate())
    }

    func testStampsMissingTimestampForExistingInstalls() {
        store.set(.onboardingCompletedAt, value: 0)
        XCTAssertFalse(makePrompt(daysAfterInstall: 0).evaluate())
        XCTAssertEqual(store.get(.onboardingCompletedAt), installedAt.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertTrue(makePrompt(daysAfterInstall: 7.1).evaluate())
    }
}
