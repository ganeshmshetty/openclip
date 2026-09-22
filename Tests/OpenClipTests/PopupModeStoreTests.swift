import XCTest
import Core
@testable import OpenClip

@MainActor
final class PopupModeStoreTests: XCTestCase {

    func testStoreDefaults() {
        let store = PopupModeStore()
        XCTAssertEqual(store.mode, .actions)
        XCTAssertNil(store.resultCard)
    }

    func testContentModePublishesResultCard() {
        let store = PopupModeStore()
        let payload = ResultCardPayload(text: "hi", isError: false, title: "AI Tools")
        store.resultCard = payload
        store.mode = .content
        XCTAssertEqual(store.mode, PopupMode.content)
        XCTAssertEqual(store.resultCard?.text, "hi")
        XCTAssertEqual(store.resultCard?.title, "AI Tools")
    }

    func testResultCardPayloadFlagsError() {
        let payload = ResultCardPayload(text: "boom", isError: true)
        XCTAssertTrue(payload.isError)
        XCTAssertEqual(payload.title, String(localized: "AI Tools"))
    }

    // MARK: - Inline decision outcomes

    func testDecisionOutcomeClearsAfterItsDisplayDuration() async throws {
        XCTAssertEqual(PopupModeStore.decisionOutcomeDisplayDuration, 5)
        let store = PopupModeStore()
        store.markDecisionRunning("decision.tool.edible")
        XCTAssertEqual(store.decisionStates["decision.tool.edible"], .running)

        store.settleDecision("decision.tool.edible", state: .no, clearAfter: 0.1)
        XCTAssertEqual(store.decisionStates["decision.tool.edible"], .no)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(store.decisionStates["decision.tool.edible"], "the outcome must fade back to the icon")
    }

    func testRerunningADecisionCancelsThePendingClear() async throws {
        let store = PopupModeStore()
        store.settleDecision("d", state: .yes, clearAfter: 0.1)
        store.markDecisionRunning("d")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(store.decisionStates["d"], .running, "a new run must not be wiped by the previous outcome's timer")

        store.settleDecision("d", state: .unsure, clearAfter: 10)
        store.clearDecision("d")
        XCTAssertNil(store.decisionStates["d"])

        store.settleDecision("e", state: .answer("billing"), clearAfter: 10)
        store.clearDecisionStates()
        XCTAssertTrue(store.decisionStates.isEmpty)
    }
}
