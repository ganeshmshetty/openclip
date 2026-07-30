import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class TextRetrieverTests: XCTestCase {
    @MainActor
    func testTextRetrieverRetrievesSelectedText() async throws {
        let retriever = MacTextRetriever()
        
        let currentApp = NSRunningApplication.current
        
        // Simulate a Cmd+C successfully changing the pasteboard shortly after retrieval starts
        Task {
            try? await Task.sleep(nanoseconds: UInt64((Constants.elementTimeout + 0.1) * 1_000_000_000))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("MockedSelection", forType: .string)
        }
        
        // Let MacTextRetriever do its thing. Accessibility will fail, it will fall back to pasteboard,
        // post Cmd+C, and wait. The background task above will increment changeCount, causing it to succeed.
        let text = await retriever.retrieveText(for: currentApp)
        
        XCTAssertEqual(text, "MockedSelection", "MacTextRetriever should retrieve the selected text from the pasteboard when changeCount increments")
        
        // Wait for pasteboard restoration to prevent test pollution
        try? await Task.sleep(nanoseconds: UInt64((Constants.pasteboardRestoreDelay + 0.1) * 1_000_000_000))
    }
}
