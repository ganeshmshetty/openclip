import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class TextRetrieverTests: XCTestCase {
    @MainActor
    func testTextRetrieverRetrievesSelectedText() async throws {
        let retriever = MacTextRetriever()
        let currentApp = AppIdentity(NSRunningApplication.current)

        // MacTextRetriever only uses AX. In the test runner there is no real text selection,
        // so AX returns nil. We verify this: the retriever must NOT fall back to Cmd+C
        // (no clipboard side-effects).
        let pasteboardBefore = NSPasteboard.general.changeCount
        let text = await retriever.retrieveText(for: currentApp, policy: .default)

        // AX finds nothing → nil result.
        XCTAssertNil(text, "Retriever should return nil when there is no AX selection")

        // Clipboard must be untouched — no silent Cmd+C.
        XCTAssertEqual(NSPasteboard.general.changeCount, pasteboardBefore,
                       "Clipboard must not be modified when selection is AX-only")
    }

    func testTextResultInitialization() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let result = TextResult(text: "Hello World", bounds: bounds)
        XCTAssertEqual(result.text, "Hello World")
        XCTAssertEqual(result.bounds, bounds)
    }
}
