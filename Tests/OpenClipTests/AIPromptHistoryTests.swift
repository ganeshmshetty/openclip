import XCTest
import Core
@testable import OpenClip

/// The recent-prompt list behind the palette's recent rows: most recent first, deduplicated
/// case-insensitively, capped, persisted through the settings store.
@MainActor
final class AIPromptHistoryTests: XCTestCase {

    func testRecordingMovesToFrontDeduplicatesAndCaps() {
        var list: [String] = []
        for i in 1...10 { list = AIPromptHistory.recording("prompt \(i)", in: list) }
        XCTAssertEqual(list.count, AIPromptHistory.capacity)
        XCTAssertEqual(list.first, "prompt 10")
        XCTAssertFalse(list.contains("prompt 1"), "the oldest fall off the end")
        list = AIPromptHistory.recording("  Prompt   4 ", in: list)
        XCTAssertEqual(list.first, "Prompt 4", "re-running moves it to the front, collapsed")
        XCTAssertEqual(list.filter { $0.lowercased() == "prompt 4" }.count, 1)
        XCTAssertEqual(AIPromptHistory.recording("   ", in: list), list, "a blank prompt changes nothing")
    }

    func testHistoryPersistsThroughTheSettingsStore() {
        let store = MemorySettingsStore()
        let history = AIPromptHistory(store: store)
        history.record("rewrite to slovak")
        history.record("make it friendly")
        XCTAssertEqual(store.get(.recentAIPrompts), ["make it friendly", "rewrite to slovak"])
        XCTAssertEqual(AIPromptHistory(store: store).prompts, ["make it friendly", "rewrite to slovak"], "a fresh instance reads it back")
        history.remove("Rewrite to slovak")
        XCTAssertEqual(store.get(.recentAIPrompts), ["make it friendly"])
    }
}
