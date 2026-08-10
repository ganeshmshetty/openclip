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
}
