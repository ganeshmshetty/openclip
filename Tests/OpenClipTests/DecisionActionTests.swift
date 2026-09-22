// DecisionActionTests.swift
// OpenClipTests

import XCTest
@testable import OpenClip
@testable import Core

@MainActor
final class DecisionActionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    func testDecisionToolsLauncherChrome() {
        let launcher = DecisionToolsAction()
        XCTAssertEqual(launcher.id, "builtin.decisionTools")
        XCTAssertTrue(launcher.chrome.launchesDecisions)
        XCTAssertEqual(launcher.chrome.source, .builtin)
        XCTAssertTrue(ActionIdentity.isBuiltin(launcher))
        XCTAssertFalse(ActionIdentity.isDecisionPreset(launcher))
    }

    func testDecisionPresetIdentity() {
        let action = DecisionAction(toolID: "triage", title: "Triage", symbolName: "tray.full")
        XCTAssertTrue(ActionIdentity.isDecisionPreset(action))
        XCTAssertEqual(action.chrome.source, .decision)
        XCTAssertEqual(action.icon, .symbol("tray.full"))
    }

    func testDefaultPresetsIncludeRequiredTools() {
        let ids = Set(DecisionDefaultPresets.all.map(\.id))
        for required in ["smart_action", "triage", "reply_as", "send_to", "safe_to_share", "fix_path", "clean_this_list"] {
            XCTAssertTrue(ids.contains(required), "Missing default tool \(required)")
        }
        XCTAssertEqual(DecisionDefaultPresets.all.first(where: { $0.id == "clean_this_list" })?.bulkMode, .line)
    }

    func testReorderTools() {
        let sample = DecisionDefaultPresets.all
        let moved = DecisionServiceManager.reordering(sample, moving: "triage", toGap: 0)
        XCTAssertEqual(moved.first?.id, "triage")
    }

    func testDecisionActionIDsAreStable() {
        XCTAssertEqual(DecisionAction.actionID(forToolID: "safe_to_share"), "decision.tool.safe_to_share")
        XCTAssertEqual(DecisionAction(toolID: "triage", title: "Triage").id, DecisionAction.actionID(forToolID: "triage"))
    }

    func testInlineStateFollowsTheFirstAnswer() {
        func presentation(_ answers: [DecisionAnswer]) -> DecisionPresentation {
            DecisionPresentation(toolID: "t", toolTitle: "T", answers: answers)
        }
        XCTAssertEqual(DecisionInlineState(presentation([DecisionAnswer(id: "a", value: .noul(true))])), .yes)
        XCTAssertEqual(DecisionInlineState(presentation([DecisionAnswer(id: "a", value: .noul(false))])), .no)
        XCTAssertEqual(DecisionInlineState(presentation([DecisionAnswer(id: "a", value: .choice(["billing"]))])), .answer("billing"))
        XCTAssertEqual(DecisionInlineState(presentation([])), .unsure)
        // Below the tool's confidence threshold the glyph is a question mark, whatever the answer.
        let unsure = DecisionPresentation(
            toolID: "t", toolTitle: "T",
            answers: [DecisionAnswer(id: "a", value: .noul(true), confidence: 0.4)],
            confidence: 0.4,
            requiresConfirmation: true
        )
        XCTAssertEqual(DecisionInlineState(unsure), .unsure)
        XCTAssertEqual(DecisionInlineState.answer("x").label, "x")
        XCTAssertNil(DecisionInlineState.yes.label)
        XCTAssertNil(DecisionInlineState.unsure.label)
    }

    func testProviderTypesAreJevAndLayaOnly() {
        XCTAssertEqual(DecisionProviderType.allCases, [.jev, .laya])
        // A setting left over from the removed OpenRouter provider falls back to the default.
        XCTAssertNil(DecisionProviderType(rawValue: "openrouter"))
    }

    func testRetypedQuestionKeepsIdentityAndFillsChoiceOptions() {
        let noul = DecisionQuestion.noul(id: "primary", prompt: "Safe to share?")
        let choice = noul.retyped(as: .choice)
        XCTAssertEqual(choice.id, "primary")
        XCTAssertEqual(choice.prompt, "Safe to share?")
        XCTAssertEqual(choice.kind, .choice)
        XCTAssertEqual(choice.options, DecisionQuestion.placeholderChoiceOptions)

        let custom = DecisionQuestion.choice(id: "q", prompt: "Which?", options: ["x", "y"])
        XCTAssertEqual(custom.retyped(as: .noul).retyped(as: .choice).options, ["x", "y"])
        XCTAssertEqual(noul.retyped(as: .noul), noul)
    }

    func testChoiceOptionsParseFromLinesOrCommas() {
        XCTAssertEqual(DecisionQuestion.parseChoiceOptions("billing, engineering ,sales"), ["billing", "engineering", "sales"])
        XCTAssertEqual(DecisionQuestion.parseChoiceOptions("Yes\n\nno\nyes, Maybe"), ["Yes", "no", "Maybe"])
        XCTAssertEqual(DecisionQuestion.parseChoiceOptions("  ,\n "), [])
        XCTAssertFalse(DecisionChoicesField.isValid(kind: .choice, text: "only one"))
        XCTAssertTrue(DecisionChoicesField.isValid(kind: .choice, text: "a, b"))
        XCTAssertTrue(DecisionChoicesField.isValid(kind: .noul, text: ""))
    }

    func testLegacyScoreKindDecodesAsYesNo() throws {
        let json = Data(#"{"id":"q","kind":"score","prompt":"How urgent?","options":[],"allowsMultiple":false}"#.utf8)
        let question = try JSONDecoder().decode(DecisionQuestion.self, from: json)
        XCTAssertEqual(question.kind, .noul)
        XCTAssertEqual(question.prompt, "How urgent?")
    }

    func testLiveAssistIsActiveDuringMenuBarWindow() {
        let manager = DecisionServiceManager.shared
        let store = DefaultSettingsStore.shared
        let previousEnabled = store.get(.decisionLiveAssistEnabled)
        let previousUntil = store.get(.decisionLiveAssistUntilTimestamp)
        defer {
            store.set(.decisionLiveAssistEnabled, value: previousEnabled)
            store.set(.decisionLiveAssistUntilTimestamp, value: previousUntil)
        }

        store.set(.decisionLiveAssistEnabled, value: false)
        store.set(.decisionLiveAssistUntilTimestamp, value: 0.0)
        XCTAssertFalse(manager.isLiveAssistActive)
        XCTAssertEqual(manager.liveAssistRemainingSeconds, 0)

        store.set(.decisionLiveAssistUntilTimestamp, value: Date().timeIntervalSince1970 + 600)
        XCTAssertTrue(manager.isLiveAssistActive)
        XCTAssertGreaterThan(manager.liveAssistRemainingSeconds, 500)

        store.set(.decisionLiveAssistUntilTimestamp, value: Date().timeIntervalSince1970 - 1)
        XCTAssertFalse(manager.isLiveAssistActive)
        XCTAssertEqual(manager.liveAssistRemainingSeconds, 0)

        store.set(.decisionLiveAssistEnabled, value: true)
        XCTAssertTrue(manager.isLiveAssistActive)
    }

    func testMockProviderEvaluateNoul() async throws {
        let mock = MockDecisionProvider(response: DecisionResponse(
            answers: [DecisionAnswer(id: "share.safe", value: .noul(true), confidence: 0.95)],
            confidence: 0.95
        ))
        let manager = DecisionServiceManager.shared
        let previous = manager.providerOverride
        manager.providerOverride = mock
        defer { manager.providerOverride = previous }

        let tool = try XCTUnwrap(DecisionDefaultPresets.all.first { $0.id == "safe_to_share" })
        let presentation = try await manager.evaluate(tool: tool, text: "Public blog draft")
        XCTAssertEqual(presentation.toolID, "safe_to_share")
        XCTAssertFalse(presentation.requiresConfirmation)
        XCTAssertEqual(presentation.answers.first?.value, .noul(true))
    }

    /// Low confidence is not an error: the answer comes back flagged unsure, which the popup draws
    /// as a grey question mark instead of a tick or cross.
    func testLowConfidenceIsUnsureNotAnError() async throws {
        let mock = MockDecisionProvider(response: DecisionResponse(
            answers: [DecisionAnswer(id: "share.safe", value: .noul(true), confidence: 0.1)],
            confidence: 0.1
        ))
        let manager = DecisionServiceManager.shared
        let previous = manager.providerOverride
        manager.providerOverride = mock
        defer { manager.providerOverride = previous }

        let tool = try XCTUnwrap(DecisionDefaultPresets.all.first { $0.id == "safe_to_share" })
        let presentation = try await manager.evaluate(tool: tool, text: "secrets")
        XCTAssertTrue(presentation.requiresConfirmation)
        XCTAssertEqual(presentation.confidence, 0.1)
        XCTAssertEqual(DecisionInlineState(presentation), .unsure)
    }

    /// A tree walk that cannot settle (fail-closed branch) also ends unsure rather than throwing.
    func testTreeThatFailsClosedEndsUnsure() {
        let tool = DecisionToolPreset(id: "t", title: "T", questions: [.noul(id: "q", prompt: "?")])
        let presentation = DecisionServiceManager.unsurePresentation(tool: tool, answers: [], confidence: 0.2)
        XCTAssertTrue(presentation.requiresConfirmation)
        XCTAssertEqual(presentation.chips, ["Unsure"])
        XCTAssertEqual(DecisionInlineState(presentation), .unsure)
    }
}

@MainActor
final class MockDecisionProvider: DecisionProvider {
    let type: DecisionProviderType = .laya
    let response: DecisionResponse
    init(response: DecisionResponse) { self.response = response }
    func availability() async -> DecisionProviderAvailability { .available }
    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        guard !request.state.isEmpty else { throw DecisionError.emptyInput }
        return response
    }
}
