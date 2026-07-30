import XCTest
import AppKit
@testable import OpenClip

final class TextRetrieverTests: XCTestCase {
    func testTextRetrieverInstantiates() async {
        let retriever = TextRetriever()
        XCTAssertNotNil(retriever)
        
        let currentApp = NSRunningApplication.current
        // Verify it does not crash when asked to retrieve text from the current app
        let text = await retriever.retrieveText(for: currentApp)
        // It could be nil or a string, just verify execution completes.
        XCTAssertTrue(true, "TextRetriever completed execution")
    }
}
