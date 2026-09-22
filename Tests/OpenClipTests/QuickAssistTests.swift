// QuickAssistTests.swift
// OpenClipTests
//
// Quick Assist: the per-tool flag and its tolerant decoding, the batched request that asks every
// Quick Assist tool in one pass, mapping the batched answers back onto rows, and where the
// floating window opens.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class QuickAssistTests: XCTestCase {

    // MARK: - The flag

    func testPresetDecodesWithoutTheQuickAssistKey() throws {
        // A preset saved before Quick Assist existed: every field added since must default rather
        // than throw, or one missing key discards the user's whole tool list.
        let legacy = Data(#"{"id":"custom_1","title":"Edible?","questions":[]}"#.utf8)
        let preset = try JSONDecoder().decode(DecisionToolPreset.self, from: legacy)
        XCTAssertEqual(preset.id, "custom_1")
        XCTAssertEqual(preset.title, "Edible?")
        XCTAssertFalse(preset.showsInQuickAssist)
        XCTAssertTrue(preset.isEnabled)
        XCTAssertEqual(preset.bulkMode, .none)
        XCTAssertEqual(preset.confirmBelowConfidence, 0.72)

        let roundTripped = try JSONDecoder().decode(
            DecisionToolPreset.self,
            from: try JSONEncoder().encode(DecisionToolPreset(id: "x", title: "X", questions: [], showsInQuickAssist: true))
        )
        XCTAssertTrue(roundTripped.showsInQuickAssist)
    }

    func testSafeToShareShipsInQuickAssistAndTreeBulkToolsDoNot() throws {
        let defaults = DecisionDefaultPresets.all
        let safeToShare = try XCTUnwrap(defaults.first { $0.id == "safe_to_share" })
        XCTAssertTrue(safeToShare.showsInQuickAssist, "the as-you-type default should answer out of the box")

        for tool in defaults where tool.treeID != nil || tool.bulkMode != .none {
            XCTAssertFalse(tool.showsInQuickAssist, "\(tool.id) is multi-request and cannot answer as you type")
        }
    }

    func testQuickAssistToolsExcludeDisabledTreeAndBulkTools() {
        let engine = DecisionLiveAssistEngine()
        let manager = DecisionServiceManager.shared
        let previous = manager.tools
        defer { manager.tools = previous }

        manager.tools = [
            DecisionToolPreset(id: "yes", title: "Yes tool", questions: [.noul(id: "q", prompt: "?")], showsInQuickAssist: true),
            DecisionToolPreset(id: "off", title: "Not marked", questions: [.noul(id: "q", prompt: "?")], showsInQuickAssist: false),
            DecisionToolPreset(id: "disabled", title: "Disabled", questions: [.noul(id: "q", prompt: "?")], isEnabled: false, showsInQuickAssist: true),
            DecisionToolPreset(id: "tree", title: "Tree", questions: [.noul(id: "q", prompt: "?")], treeID: "t", showsInQuickAssist: true),
            DecisionToolPreset(id: "bulk", title: "Bulk", questions: [.noul(id: "q", prompt: "?")], bulkMode: .line, showsInQuickAssist: true),
            DecisionToolPreset(id: "empty", title: "No questions", questions: [], showsInQuickAssist: true),
        ]
        XCTAssertEqual(engine.quickAssistTools.map(\.id), ["yes"])
    }

    // MARK: - One request for every tool

    func testBatchedQuestionsNamespaceEachToolsPrimaryQuestion() {
        let tools = [
            DecisionToolPreset(id: "safe_to_share", title: "Safe?", questions: [
                .noul(id: "share.safe", prompt: "Safe to share?"),
                .noul(id: "ignored", prompt: "second questions stay out of the batch"),
            ]),
            DecisionToolPreset(id: "dept", title: "Team", questions: [
                .choice(id: "team", prompt: "Which team?", options: ["billing", "sales"]),
            ]),
        ]
        let questions = DecisionLiveAssistEngine.batchedQuestions(for: tools)
        XCTAssertEqual(questions.map(\.id), ["qa.safe_to_share", "qa.dept"])
        XCTAssertEqual(questions[0].kind, .noul)
        XCTAssertEqual(questions[1].kind, .choice)
        XCTAssertEqual(questions[1].options, ["billing", "sales"], "a choice keeps the labels the user typed")
        XCTAssertEqual(questions[0].prompt, "Safe to share?")
    }

    func testRowsMapBatchedAnswersBackPerToolAndHonourEachThreshold() {
        let tools = [
            DecisionToolPreset(id: "safe", title: "Safe?", questions: [.noul(id: "q", prompt: "?")], confirmBelowConfidence: 0.85),
            DecisionToolPreset(id: "team", title: "Team", questions: [.choice(id: "q", prompt: "?", options: ["billing"])], confirmBelowConfidence: 0.5),
            DecisionToolPreset(id: "shaky", title: "Shaky", questions: [.noul(id: "q", prompt: "?")], confirmBelowConfidence: 0.9),
            DecisionToolPreset(id: "missing", title: "Unanswered", questions: [.noul(id: "q", prompt: "?")]),
        ]
        let response = DecisionResponse(answers: [
            DecisionAnswer(id: "qa.safe", value: .noul(false), confidence: 0.95),
            DecisionAnswer(id: "qa.team", value: .choice(["billing"]), confidence: 0.7),
            DecisionAnswer(id: "qa.shaky", value: .noul(true), confidence: 0.6),
        ], confidence: 0.6)

        let rows = DecisionLiveAssistEngine.rows(from: response, tools: tools)
        XCTAssertEqual(rows.map(\.id), ["safe", "team", "shaky", "missing"])
        XCTAssertEqual(rows.map(\.title), ["Safe?", "Team", "Shaky", "Unanswered"])
        XCTAssertEqual(rows[0].state, .no, "0.95 clears the 0.85 threshold")
        XCTAssertEqual(rows[1].state, .answer("billing"))
        XCTAssertEqual(rows[2].state, .unsure, "0.6 is under this tool's 0.9 threshold")
        XCTAssertEqual(rows[3].state, .unsure, "a tool the provider skipped reads as unsure, never as a wrong yes")
    }

    // MARK: - The floating window

    func testWindowOpensBottomRightUntilItIsMovedThenRemembersWhereItWasLeft() {
        let store = MemorySettingsStore()
        let controller = QuickAssistPanelController(settingsStore: store)
        let size = NSSize(width: 248, height: 120)
        let visible = try? XCTUnwrap(NSScreen.main).visibleFrame
        guard let visible else { return XCTFail("no screen") }

        let fresh = controller.restoredOrigin(for: size)
        XCTAssertEqual(fresh.x, visible.maxX - size.width - QuickAssistPanelController.screenMargin, accuracy: 0.5)
        XCTAssertEqual(fresh.y, visible.minY + QuickAssistPanelController.screenMargin, accuracy: 0.5)

        let moved = NSPoint(x: visible.minX + 40, y: visible.minY + 300)
        store.set(.quickAssistOriginX, value: Double(moved.x))
        store.set(.quickAssistOriginY, value: Double(moved.y))
        XCTAssertEqual(controller.restoredOrigin(for: size).x, moved.x, accuracy: 0.5)
        XCTAssertEqual(controller.restoredOrigin(for: size).y, moved.y, accuracy: 0.5)

        // A position from a screen that is no longer connected falls back to the corner.
        store.set(.quickAssistOriginX, value: -90_000)
        store.set(.quickAssistOriginY, value: -90_000)
        XCTAssertEqual(controller.restoredOrigin(for: size).x, fresh.x, accuracy: 0.5)
    }

    func testEngineShowsAHintWithNoToolsAndWaitsForEnoughText() {
        let engine = DecisionLiveAssistEngine()
        let manager = DecisionServiceManager.shared
        let previousTools = manager.tools
        let store = DefaultSettingsStore.shared
        let previousEnabled = store.get(.decisionLiveAssistEnabled)
        defer {
            manager.tools = previousTools
            store.set(.decisionLiveAssistEnabled, value: previousEnabled)
        }
        store.set(.decisionLiveAssistEnabled, value: true)

        manager.tools = [DecisionToolPreset(id: "none", title: "Not in quick assist", questions: [.noul(id: "q", prompt: "?")])]
        engine.schedule(text: "a long enough sentence to judge")
        XCTAssertTrue(engine.rows.isEmpty)
        XCTAssertEqual(engine.statusLine, String(localized: "No tools yet. Turn on “Show in Quick Assist” for a tool in Settings → Decisions."))

        manager.tools = [DecisionToolPreset(id: "qa", title: "QA", questions: [.noul(id: "q", prompt: "?")], showsInQuickAssist: true)]
        engine.schedule(text: "short")
        XCTAssertTrue(engine.rows.isEmpty, "a few characters are not worth judging")
        XCTAssertEqual(engine.statusLine, String(localized: "Start typing and answers appear here."))

        // Enough text: the rows appear immediately as spinners, before the provider answers.
        engine.schedule(text: "this is long enough to be judged")
        XCTAssertEqual(engine.rows.map(\.state), [.running])
        XCTAssertNil(engine.statusLine)
        engine.deactivate()
        XCTAssertTrue(engine.rows.isEmpty)
    }
}
