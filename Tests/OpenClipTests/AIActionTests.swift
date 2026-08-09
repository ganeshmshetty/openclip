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

    func testPerformReturnsContentTree() async throws {
        let action = AIAction(presetID: "proofread", title: "Proofread")
        let context = makeContext(text: "teh text")
        
        let result = try await action.perform(context)
        
        guard case .keepVisible(let inner) = result,
              case .showContent(let tree, let header) = inner else {
            XCTFail("Expected .keepVisible(.showContent(...)), got \(result)")
            return
        }
        
        XCTAssertEqual(header?.title, "Proofread")
        XCTAssertEqual(header?.icon, "sparkles")
        
        guard case .stack(_, let children) = tree else {
            XCTFail("Expected stack tree root, got \(tree)")
            return
        }
        
        guard children.count == 2 else {
            XCTFail("Expected stack to have 2 children, got \(children.count)")
            return
        }
        guard case .text(let textProps) = children[0] else {
            XCTFail("Expected text component at index 0")
            return
        }
        XCTAssertFalse(textProps.content.isEmpty)
        
        guard case .stack(let hstackProps, let btnChildren) = children[1] else {
            XCTFail("Expected horizontal stack for buttons at index 1")
            return
        }
        XCTAssertEqual(hstackProps.orientation, .horizontal)
        guard btnChildren.count == 2 else {
            XCTFail("Expected horizontal stack to have 2 children, got \(btnChildren.count)")
            return
        }
        
        guard case .button(let replaceBtn) = btnChildren[0] else {
            XCTFail("Expected Replace button at index 0 of horizontal stack")
            return
        }
        XCTAssertEqual(replaceBtn.title, "Replace")
        XCTAssertEqual(replaceBtn.icon, CanvasIconSource.symbol("arrow.triangle.2.circlepath"))
        XCTAssertEqual(replaceBtn.handler, CanvasHandler.effect(.paste(textProps.content)))
        
        guard case .button(let copyBtn) = btnChildren[1] else {
            XCTFail("Expected Copy button at index 1 of horizontal stack")
            return
        }
        XCTAssertEqual(copyBtn.title, "Copy")
        XCTAssertEqual(copyBtn.icon, CanvasIconSource.symbol("doc.on.doc"))
        XCTAssertEqual(copyBtn.handler, CanvasHandler.effect(.copy(textProps.content)))
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
