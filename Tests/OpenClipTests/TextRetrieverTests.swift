import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class TextRetrieverTests: XCTestCase {
    @MainActor
    func testTextRetrieverRetrievesSelectedText() async throws {
        let retriever = MacTextRetriever()
        let currentApp = AppIdentity(NSRunningApplication.current)

        // In the test runner there is no real text selection, so the AX read and the copy-based
        // fallbacks all produce no text. The retriever must surface nil rather than a stale
        // clipboard value. (Copy fallbacks may transiently touch the pasteboard and restore it;
        // the engine never returns non-empty text for an empty selection.)
        let text = await retriever.retrieveText(for: currentApp, policy: .default)

        XCTAssertNil(text, "Retriever should return nil when there is no selection")
    }

    func testTextResultInitialization() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let result = TextResult(text: "Hello World", bounds: bounds)
        XCTAssertEqual(result.text, "Hello World")
        XCTAssertEqual(result.bounds, bounds)
    }
}
