import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class OpenClipSnippetParserTests: XCTestCase {
    func testParseJavaScriptSnippetProducesJavaScriptAction() async {
        let snippet = """
        # Title: UpperJS
        # Icon: symbol:textformat
        js:
        return selection.toUpperCase();
        """
        
        let action = await OpenClipSnippetParser.parse(snippet: snippet)
        XCTAssertTrue(action is JavaScriptAction, "Expected JavaScriptAction but got \(String(describing: action))")
        if let jsAction = action as? JavaScriptAction {
            XCTAssertEqual(jsAction.title, "UpperJS")
            XCTAssertEqual(jsAction.scriptCode.trimmingCharacters(in: .whitespacesAndNewlines), "return selection.toUpperCase();")
        }
    }
    
    func testParseAppleScriptSnippetProducesAppleScriptAction() async {
        let snippet = """
        # Title: LowerAppleScript
        # Icon: symbol:applescript
        applescript:
        return "hello"
        """
        
        let action = await OpenClipSnippetParser.parse(snippet: snippet)
        XCTAssertTrue(action is AppleScriptAction, "Expected AppleScriptAction but got \(String(describing: action))")
        if let appleAction = action as? AppleScriptAction {
            XCTAssertEqual(appleAction.title, "LowerAppleScript")
            XCTAssertEqual(appleAction.appleScriptCode.trimmingCharacters(in: .whitespacesAndNewlines), "return \"hello\"")
        }
    }

    func testParseURLSnippetProducesURLTemplateAction() async {
        let snippet = """
        # Title: Search Google
        # Icon: symbol:magnifyingglass
        url:
        https://www.google.com/search?q={query}
        """
        
        let action = await OpenClipSnippetParser.parse(snippet: snippet)
        XCTAssertTrue(action is URLTemplateAction, "Expected URLTemplateAction but got \(String(describing: action))")
    }

    func testParseInvalidSnippetReturnsNil() async {
        let snippet = """
        Title: Plain Text
        This is not a valid snippet header.
        """
        
        let action = await OpenClipSnippetParser.parse(snippet: snippet)
        XCTAssertNil(action)
    }

    func testParseScriptBodyWithEmbeddedComments() async {
        let snippet = """
        # Title: CommentJS
        # Icon: symbol:terminal
        js:
        // icon: custom
        // title: overridden
        return selection.toLowerCase();
        """
        
        let action = await OpenClipSnippetParser.parse(snippet: snippet)
        XCTAssertTrue(action is JavaScriptAction, "Expected JavaScriptAction but got \(String(describing: action))")
        if let jsAction = action as? JavaScriptAction {
            XCTAssertEqual(jsAction.title, "CommentJS")
            XCTAssertTrue(jsAction.scriptCode.contains("// icon: custom"))
            XCTAssertTrue(jsAction.scriptCode.contains("// title: overridden"))
        }
    }
}
