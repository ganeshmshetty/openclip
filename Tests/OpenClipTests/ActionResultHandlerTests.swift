import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionResultHandlerTests: XCTestCase {
    func testCopyResultHandler() async throws {
        let handler = DefaultActionResultHandler()
        let result = ActionResult.copy("Test Copy")
        try await handler.handle(result, in: nil)
        
        let pasteboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardText, "Test Copy")
    }

    /// Presentation/flow results are presenter-owned (PopupWindowController); the handler must treat
    /// them as no-ops without crashing.
    func testHandlerIgnoresShowBubble() async throws {
        let handler = DefaultActionResultHandler()
        let bubble = BubbleContent(title: "Test", rows: [.text("hi")], emphasis: .result)
        try await handler.handle(.showBubble(bubble), in: nil)
    }
}
