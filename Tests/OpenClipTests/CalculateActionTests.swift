import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class CalculateActionTests: XCTestCase {
    @MainActor
    func testCalculateActionEnabledForMath() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        
        let validMathContext = ActionContext(
            selection: SelectionContext(text: "12 + 4.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: validMathContext), "CalculateAction should be enabled for math expressions")
        
        let plainTextContext = ActionContext(
            selection: SelectionContext(text: "Hello World", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: plainTextContext), "CalculateAction should be disabled for non-math text")
    }
    
    @MainActor
    func testCalculateActionExecution() async throws {
        UserDefaults.standard.removeObject(forKey: "action.calculate.mode")
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "100 * 2.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .paste(let newText) = result {
            XCTAssertEqual(newText, "250", "Math calculation 100 * 2.5 should equal 250")
        } else {
            XCTFail("Expected paste result for CalculateAction")
        }
    }

    // MARK: - Result Bubble

    @MainActor
    func testResultBubbleFooterOptions() async {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "12 * 12", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )

        guard let bubble = await action.makeBubble(for: context) else {
            return XCTFail("Expected a result bubble")
        }
        XCTAssertEqual(bubble.title, "Calculate")
        XCTAssertEqual(bubble.subtitle, "12 * 12 = 144")
        XCTAssertEqual(
            bubble.footer.map(\.title),
            ["Paste 144", "Copy 144", "Copy 12 * 12 = 144"]
        )
    }

    @MainActor
    func testResultBubbleNilForNonMath() async {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "Hello World", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )

        let bubble = await action.makeBubble(for: context)
        XCTAssertNil(bubble)
    }
}
