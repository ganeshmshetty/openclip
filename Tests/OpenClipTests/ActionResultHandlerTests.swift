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
}
