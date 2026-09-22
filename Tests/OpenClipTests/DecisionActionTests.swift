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

    func testLowConfidenceFailClosed() async {
        let mock = MockDecisionProvider(response: DecisionResponse(
            answers: [DecisionAnswer(id: "share.safe", value: .noul(true), confidence: 0.1)],
            confidence: 0.1
        ))
        let manager = DecisionServiceManager.shared
        let previous = manager.providerOverride
        manager.providerOverride = mock
        defer { manager.providerOverride = previous }

        let tool = DecisionDefaultPresets.all.first { $0.id == "safe_to_share" }!
        do {
            _ = try await manager.evaluate(tool: tool, text: "secrets")
            XCTFail("Expected lowConfidence")
        } catch let error as DecisionError {
            XCTAssertEqual(error, .lowConfidence)
        } catch {
            XCTFail("Unexpected \(error)")
        }
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
