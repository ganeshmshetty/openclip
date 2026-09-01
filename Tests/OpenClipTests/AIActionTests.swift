// AIActionTests.swift
// OpenClipTests

import XCTest
@testable import OpenClip
@testable import Core

@MainActor
final class AIActionTests: XCTestCase {
    private func makeContext(text: String) -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection)
    }

    func testPerformReturnsSuccessWhenSelectionIsEmpty() async throws {
        let action = AIAction(presetID: "proofread", title: "Proofread")
        let context = makeContext(text: "")
        
        let result = try await action.perform(context)
        guard case .success = result else {
            XCTFail("Expected .success, got \(result)")
            return
        }
    }

    func testAIActionIconDefaultMatchesPresetIcon() {
        let action = AIAction(presetID: "proofread", title: "Proofread")
        XCTAssertEqual(action.icon, .text("Proofread"))
    }

    func testAIActionIconForPreset() {
        XCTAssertEqual(AIAction.iconForPreset(presetID: "proofread"), .text("Proofread"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "rewrite"), .text("Rewrite"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "summarize"), .text("Summarize"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "explain"), .text("Explain"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "translate"), .text("Translate"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "fix_code"), .text("Fix Code"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "make_shorter"), .text("Make Shorter"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "formal_tone"), .text("Formal Tone"))
        XCTAssertEqual(AIAction.iconForPreset(presetID: "custom_other"), .text("custom_other"))
    }
}
