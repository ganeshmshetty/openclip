import XCTest
@testable import Core

final class ActionResultAdapterTests: XCTestCase {
    // MARK: - copyResult / pasteResult overrides

    func testCopyResultOverridesPasteAndCopy() {
        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        if case .copy(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromPaste)")
        }

        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        if case .copy(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromCopy)")
        }
    }

    func testPasteResultOverridesCopyAndPaste() {
        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .pasteResult, stayVisible: false, title: "T", icon: nil)
        if case .paste(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromCopy)")
        }

        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .pasteResult, stayVisible: false, title: "T", icon: nil)
        if case .paste(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromPaste)")
        }
    }

    // MARK: - showResult → content card with Paste/Copy footer

    func testShowResultWrapsCopyInContent() {
        let result = ActionResultAdapter.apply(raw: .copy("x"), after: .showResult, stayVisible: false, title: "My Title", icon: "doc.text")
        guard case .showContent(let content) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        XCTAssertEqual(content.title, "My Title")
        XCTAssertEqual(content.icon, "doc.text")
        XCTAssertEqual(content.emphasis, .result)
        XCTAssertEqual(content.rows.count, 1)
        guard case .text(let rowText) = content.rows[0] else {
            return XCTFail("Expected text row")
        }
        XCTAssertEqual(rowText, "x")
        XCTAssertEqual(content.footer.count, 2)
        XCTAssertEqual(content.footer[0].title, "Paste")
        guard case .perform(.paste("x")) = content.footer[0].outcome else {
            return XCTFail("Expected Paste footer performing .paste(x)")
        }
        XCTAssertEqual(content.footer[1].title, "Copy")
        guard case .perform(.copy("x")) = content.footer[1].outcome else {
            return XCTFail("Expected Copy footer performing .copy(x)")
        }
    }

    func testShowResultWrapsPasteInContent() {
        let result = ActionResultAdapter.apply(raw: .paste("x"), after: .showResult, stayVisible: false, title: "T", icon: nil)
        guard case .showContent(let content) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        XCTAssertEqual(content.rows.count, 1)
    }

    // MARK: - none collapses to success

    func testNoneReturnsSuccessForAnyRaw() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .none, stayVisible: false, title: "T", icon: nil)
        guard case .success = copy else {
            return XCTFail("Expected .success, got \(copy)")
        }

        let openURL = ActionResultAdapter.apply(raw: .openURL(URL(string: "https://example.com")!), after: .none, stayVisible: false, title: "T", icon: nil)
        guard case .success = openURL else {
            return XCTFail("Expected .success, got \(openURL)")
        }
    }

    // MARK: - default passes raw through

    func testDefaultPassesThroughRaw() {
        let url = URL(string: "https://example.com")!
        let openURL = ActionResultAdapter.apply(raw: .openURL(url), after: .default, stayVisible: false, title: "T", icon: nil)
        guard case .openURL(let target) = openURL else {
            return XCTFail("Expected .openURL, got \(openURL)")
        }
        XCTAssertEqual(target, url)

        let cut = ActionResultAdapter.apply(raw: .cut("x"), after: .default, stayVisible: false, title: "T", icon: nil)
        guard case .cut(let text) = cut else {
            return XCTFail("Expected .cut, got \(cut)")
        }
        XCTAssertEqual(text, "x")
    }

    // MARK: - presentations pass through untouched

    func testPresentationsPassThroughUnchanged() {
        let content = ActionResultAdapter.apply(raw: .showContent(PopupContent(title: "B")), after: .copyResult, stayVisible: true, title: "T", icon: nil)
        guard case .showContent(let content) = content else {
            return XCTFail("Expected .showContent passthrough, got \(content)")
        }
        XCTAssertEqual(content.title, "B")

        let status = ActionResultAdapter.apply(raw: .showStatus(StatusFeedback(message: "s", style: .info)), after: .pasteResult, stayVisible: false, title: "T", icon: nil)
        guard case .showStatus(let feedback) = status else {
            return XCTFail("Expected .showStatus passthrough, got \(status)")
        }
        XCTAssertEqual(feedback.message, "s")

        let config = ActionResultAdapter.apply(raw: .openConfiguration(ConfigurationRequest(actionID: "a")), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        guard case .openConfiguration(let request) = config else {
            return XCTFail("Expected .openConfiguration passthrough, got \(config)")
        }
        XCTAssertEqual(request.actionID, "a")

        let keyPress = ActionResultAdapter.apply(raw: .keyPress(KeyPressSpec(key: "b")), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        guard case .keyPress(let spec) = keyPress else {
            return XCTFail("Expected .keyPress passthrough, got \(keyPress)")
        }
        XCTAssertEqual(spec.key, "b")

        let shortcut = ActionResultAdapter.apply(raw: .runShortcut(name: "n", input: "i"), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        guard case .runShortcut(name: "n", input: "i") = shortcut else {
            return XCTFail("Expected .runShortcut passthrough, got \(shortcut)")
        }

        let keepVisible = ActionResultAdapter.apply(raw: .keepVisible(.copy("x")), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        guard case .keepVisible(.copy("x")) = keepVisible else {
            return XCTFail("Expected .keepVisible passthrough, got \(keepVisible)")
        }

        let sequence = ActionResultAdapter.apply(raw: .sequence([.copy("a"), .copy("b")]), after: .copyResult, stayVisible: false, title: "T", icon: nil)
        guard case .sequence(let items) = sequence else {
            return XCTFail("Expected .sequence passthrough, got \(sequence)")
        }
        XCTAssertEqual(items.count, 2)

        // A dismissing sequence is still wrapped by stayVisible (every item dismisses), matching
        // the plan: passthrough happens first, then the stayVisible wrap applies to dismissing results.
        let wrappedSequence = ActionResultAdapter.apply(raw: .sequence([.copy("a"), .copy("b")]), after: .copyResult, stayVisible: true, title: "T", icon: nil)
        guard case .keepVisible(.sequence(let wrappedItems)) = wrappedSequence else {
            return XCTFail("Expected .keepVisible(.sequence) under stayVisible, got \(wrappedSequence)")
        }
        XCTAssertEqual(wrappedItems.count, 2)
    }

    // MARK: - stayVisible wraps only when the normalized result would dismiss

    func testStayVisibleWrapsDismissingResult() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .default, stayVisible: true, title: "T", icon: nil)
        guard case .keepVisible(.copy("x")) = copy else {
            return XCTFail("Expected .keepVisible(.copy), got \(copy)")
        }

        let paste = ActionResultAdapter.apply(raw: .paste("x"), after: .default, stayVisible: true, title: "T", icon: nil)
        guard case .keepVisible(.paste("x")) = paste else {
            return XCTFail("Expected .keepVisible(.paste), got \(paste)")
        }

        let url = URL(string: "https://example.com")!
        let openURL = ActionResultAdapter.apply(raw: .openURL(url), after: .default, stayVisible: true, title: "T", icon: nil)
        guard case .keepVisible(.openURL(let target)) = openURL else {
            return XCTFail("Expected .keepVisible(.openURL), got \(openURL)")
        }
        XCTAssertEqual(target, url)
    }

    func testStayVisibleDoesNotWrapPresentations() {
        let content = ActionResultAdapter.apply(raw: .showContent(PopupContent(title: "B")), after: .default, stayVisible: true, title: "T", icon: nil)
        guard case .showContent = content else {
            return XCTFail("Expected unwrapped .showContent, got \(content)")
        }

        let status = ActionResultAdapter.apply(raw: .showStatus(StatusFeedback(message: "s", style: .info)), after: .default, stayVisible: true, title: "T", icon: nil)
        guard case .showStatus = status else {
            return XCTFail("Expected unwrapped .showStatus, got \(status)")
        }
    }

    func testStayVisibleFalseLeavesResultUnwrapped() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .default, stayVisible: false, title: "T", icon: nil)
        guard case .copy(let text) = copy else {
            return XCTFail("Expected .copy, got \(copy)")
        }
        XCTAssertEqual(text, "x")
    }
}
