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

    // MARK: - showResult → component tree with Paste/Copy buttons

    func testShowResultWrapsCopyInContentTree() {
        let result = ActionResultAdapter.apply(raw: .copy("x"), after: .showResult, stayVisible: false, title: "My Title", icon: "doc.text")
        guard case .showContent(let tree, let header) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        XCTAssertEqual(header?.title, "My Title")
        XCTAssertEqual(header?.icon, "doc.text")
        guard case .stack(_, let children) = tree else {
            return XCTFail("Expected stack root node")
        }
        XCTAssertEqual(children.count, 3)
        guard case .text(let textProps) = children[0] else {
            return XCTFail("Expected text component")
        }
        XCTAssertEqual(textProps.content, "x")

        guard case .button(let pasteBtn) = children[1] else {
            return XCTFail("Expected Paste button")
        }
        XCTAssertEqual(pasteBtn.title, "Paste")
        XCTAssertEqual(pasteBtn.icon, .symbol("arrow.triangle.2.circlepath"))
        XCTAssertEqual(pasteBtn.handler, .effect(.paste("x")))

        guard case .button(let copyBtn) = children[2] else {
            return XCTFail("Expected Copy button")
        }
        XCTAssertEqual(copyBtn.title, "Copy")
        XCTAssertEqual(copyBtn.icon, .symbol("doc.on.doc"))
        XCTAssertEqual(copyBtn.handler, .effect(.copy("x")))
    }

    func testShowResultWrapsPasteInContentTree() {
        let result = ActionResultAdapter.apply(raw: .paste("x"), after: .showResult, stayVisible: false, title: "T", icon: nil)
        guard case .showContent(let tree, let header) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        XCTAssertEqual(header?.title, "T")
        XCTAssertNil(header?.icon)
        guard case .stack(_, let children) = tree else {
            return XCTFail("Expected stack root node")
        }
        XCTAssertEqual(children.count, 3)
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
        let content = ActionResultAdapter.apply(raw: .showContent(.text(CanvasTextProps(content: "B")), nil), after: .copyResult, stayVisible: true, title: "T", icon: nil)
        guard case .showContent(let tree, _) = content, case .text(let props) = tree else {
            return XCTFail("Expected .showContent passthrough, got \(content)")
        }
        XCTAssertEqual(props.content, "B")

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
        let content = ActionResultAdapter.apply(raw: .showContent(.text(CanvasTextProps(content: "B")), nil), after: .default, stayVisible: true, title: "T", icon: nil)
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
