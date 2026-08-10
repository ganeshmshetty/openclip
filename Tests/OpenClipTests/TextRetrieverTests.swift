import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class TextRetrieverTests: XCTestCase {
    @MainActor
    func testTextRetrieverRetrievesSelectedText() async throws {
        let retriever = MacTextRetriever()
        let currentApp = AppIdentity(NSRunningApplication.current)

        // Without grabPasteboard policy, MacTextRetriever only uses AX.
        // In the test runner there is no real text selection, so AX returns nil.
        // We verify this: the retriever must NOT fall back to Cmd+C (no clipboard side-effects).
        let pasteboardBefore = NSPasteboard.general.changeCount
        let text = await retriever.retrieveText(for: currentApp, policy: .default)

        // AX finds nothing → nil result.
        XCTAssertNil(text, "Retriever should return nil when there is no AX selection and grabPasteboard is false")

        // Clipboard must be untouched — no silent Cmd+C.
        XCTAssertEqual(NSPasteboard.general.changeCount, pasteboardBefore,
                       "Clipboard must not be modified when using AX-only mode")
    }
    
    @MainActor
    func testGrabPasteboardPolicySkipsAccessibility() async throws {
        let retriever = MacTextRetriever()
        let currentApp = AppIdentity(NSRunningApplication.current)
        
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("FastMockedSelection", forType: .string)
        }
        
        let policy = AppPolicyContext(denyFormatting: false, denyProbe: false, denyPreprobe: false, grabPasteboard: true, assumePaste: false)
        
        let startTime = Date()
        let text = await retriever.retrieveText(for: currentApp, policy: policy)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(text, "FastMockedSelection", "MacTextRetriever should retrieve the selected text from the pasteboard directly")
        XCTAssertLessThan(duration, Constants.elementTimeout, "Should bypass accessibility wait time when grabPasteboard is true")
        
        try? await Task.sleep(nanoseconds: UInt64((Constants.pasteboardRestoreDelay + 0.1) * 1_000_000_000))
    }

    @MainActor
    func testGrabPasteboardPolicyAcceptsMultipleChangeCountIncrements() async throws {
        let retriever = MacTextRetriever()
        let currentApp = AppIdentity(NSRunningApplication.current)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("MultiIncrementSelection", forType: .string)
        }

        let policy = AppPolicyContext(denyFormatting: false, denyProbe: false, denyPreprobe: false, grabPasteboard: true, assumePaste: false)

        let text = await retriever.retrieveText(for: currentApp, policy: policy)

        XCTAssertEqual(text, "MultiIncrementSelection", "MacTextRetriever should accept pasteboard updates where changeCount increases by more than 1")

        try? await Task.sleep(nanoseconds: UInt64((Constants.pasteboardRestoreDelay + 0.1) * 1_000_000_000))
    }
    
    func testTextResultInitialization() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let result = TextResult(text: "Hello World", bounds: bounds)
        XCTAssertEqual(result.text, "Hello World")
        XCTAssertEqual(result.bounds, bounds)
    }
}
