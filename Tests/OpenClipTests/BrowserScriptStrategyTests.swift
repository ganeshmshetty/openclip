import XCTest
@testable import OpenClip

final class BrowserScriptStrategyTests: XCTestCase {

    // MARK: - Script source generation (pure, no live Apple Events)

    func testSafariTextScriptUsesFrontDocumentDoJavaScript() {
        let script = BrowserScriptStrategy.textScriptSource(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(script.contains("tell application id \"com.apple.Safari\""))
        XCTAssertTrue(script.contains("tell front document"))
        XCTAssertTrue(script.contains("do JavaScript \"window.getSelection().toString()\""))
        XCTAssertFalse(script.contains("active tab"))
        XCTAssertFalse(script.contains("execute javascript"))
    }

    func testSafariTechnologyPreviewAndKagiUseSafariScriptShape() {
        for bundleID in ["com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS"] {
            let script = BrowserScriptStrategy.textScriptSource(bundleIdentifier: bundleID)
            XCTAssertTrue(script.contains("tell front document"), bundleID)
            XCTAssertTrue(script.contains("do JavaScript"), bundleID)
            XCTAssertFalse(script.contains("execute javascript"), bundleID)
        }
    }

    func testChromiumTextScriptUsesActiveTabExecuteJavascript() {
        let script = BrowserScriptStrategy.textScriptSource(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(script.contains("tell application id \"com.google.Chrome\""))
        XCTAssertTrue(script.contains("tell active tab of front window"))
        XCTAssertTrue(script.contains("execute javascript \"window.getSelection().toString()\""))
        XCTAssertFalse(script.contains("front document"))
        XCTAssertFalse(script.contains("do JavaScript"))
    }

    func testFirefoxTextScriptUsesActiveTabExecuteJavascript() {
        let script = BrowserScriptStrategy.textScriptSource(bundleIdentifier: "org.mozilla.firefox")
        XCTAssertTrue(script.contains("tell active tab of front window"))
        XCTAssertTrue(script.contains("execute javascript \"window.getSelection().toString()\""))
    }

    func testArcTextScriptUsesActiveTabExecuteJavascript() {
        for bundleID in ["company.thebrowser.Browser", "company.thebrowser.dia"] {
            let script = BrowserScriptStrategy.textScriptSource(bundleIdentifier: bundleID)
            XCTAssertTrue(script.contains("tell active tab of front window"), bundleID)
            XCTAssertTrue(script.contains("execute javascript"), bundleID)
            XCTAssertFalse(script.contains("front document"), bundleID)
        }
    }

    // MARK: - Arc quote stripping (pure function)

    func testStripSurroundingQuotesRemovesOnePair() {
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes("\"selected text\""), "selected text")
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes("\"\"\"\""), "\"\"")
    }

    func testStripSurroundingQuotesLeavesUnquotedTextUntouched() {
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes("plain text"), "plain text")
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes(""), "")
    }

    func testStripSurroundingQuotesLeavesSingleQuoteUntouched() {
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes("\""), "\"")
    }

    func testStripSurroundingQuotesLeavesInteriorQuotesUntouched() {
        XCTAssertEqual(BrowserScriptStrategy.stripSurroundingQuotes("a\"b\"c"), "a\"b\"c")
    }
}