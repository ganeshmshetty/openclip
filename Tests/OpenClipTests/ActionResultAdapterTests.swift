import XCTest
@testable import Core

final class ActionResultAdapterTests: XCTestCase {
    // MARK: - copyResult / pasteResult overrides

    func testCopyResultOverridesPasteAndCopy() {
        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .copyResult, stayVisible: false)
        if case .copy(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromPaste)")
        }

        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .copyResult, stayVisible: false)
        if case .copy(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromCopy)")
        }
    }

    func testPasteResultOverridesCopyAndPaste() {
        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .pasteResult, stayVisible: false)
        if case .paste(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromCopy)")
        }

        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .pasteResult, stayVisible: false)
        if case .paste(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromPaste)")
        }
    }

    // MARK: - showResult degrades to the plain leaf result (canvas card rendering removed)

    func testShowResultDegradesToRawCopy() {
        let result = ActionResultAdapter.apply(raw: .copy("x"), after: .showResult, stayVisible: false)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "x")
    }

    func testShowResultDegradesToRawPaste() {
        let result = ActionResultAdapter.apply(raw: .paste("x"), after: .showResult, stayVisible: false)
        guard case .paste(let text) = result else {
            return XCTFail("Expected .paste, got \(result)")
        }
        XCTAssertEqual(text, "x")
    }

    // MARK: - none collapses to success

    func testNoneReturnsSuccessForAnyRaw() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .none, stayVisible: false)
        guard case .success = copy else {
            return XCTFail("Expected .success, got \(copy)")
        }

        let openURL = ActionResultAdapter.apply(raw: .openURL(URL(string: "https://example.com")!), after: .none, stayVisible: false)
        guard case .success = openURL else {
            return XCTFail("Expected .success, got \(openURL)")
        }
    }

    // MARK: - default passes raw through

    func testDefaultPassesThroughRaw() {
        let url = URL(string: "https://example.com")!
        let openURL = ActionResultAdapter.apply(raw: .openURL(url), after: .default, stayVisible: false)
        guard case .openURL(let target) = openURL else {
            return XCTFail("Expected .openURL, got \(openURL)")
        }
        XCTAssertEqual(target, url)

        let cut = ActionResultAdapter.apply(raw: .cut("x"), after: .default, stayVisible: false)
        guard case .cut(let text) = cut else {
            return XCTFail("Expected .cut, got \(cut)")
        }
        XCTAssertEqual(text, "x")
    }

    // MARK: - presentations pass through untouched

    func testPresentationsPassThroughUnchanged() {
        let status = ActionResultAdapter.apply(raw: .showStatus(StatusFeedback(message: "s", style: .info)), after: .pasteResult, stayVisible: false)
        guard case .showStatus(let feedback) = status else {
            return XCTFail("Expected .showStatus passthrough, got \(status)")
        }
        XCTAssertEqual(feedback.message, "s")

        let config = ActionResultAdapter.apply(raw: .openConfiguration(ConfigurationRequest(actionID: "a")), after: .copyResult, stayVisible: false)
        guard case .openConfiguration(let request) = config else {
            return XCTFail("Expected .openConfiguration passthrough, got \(config)")
        }
        XCTAssertEqual(request.actionID, "a")

        let keyPress = ActionResultAdapter.apply(raw: .keyPress(KeyPressSpec(key: "b")), after: .copyResult, stayVisible: false)
        guard case .keyPress(let spec) = keyPress else {
            return XCTFail("Expected .keyPress passthrough, got \(keyPress)")
        }
        XCTAssertEqual(spec.key, "b")

        let shortcut = ActionResultAdapter.apply(raw: .runShortcut(name: "n", input: "i"), after: .copyResult, stayVisible: false)
        guard case .runShortcut(name: "n", input: "i") = shortcut else {
            return XCTFail("Expected .runShortcut passthrough, got \(shortcut)")
        }

        let keepVisible = ActionResultAdapter.apply(raw: .keepVisible(.copy("x")), after: .copyResult, stayVisible: false)
        guard case .keepVisible(.copy("x")) = keepVisible else {
            return XCTFail("Expected .keepVisible passthrough, got \(keepVisible)")
        }

        let sequence = ActionResultAdapter.apply(raw: .sequence([.copy("a"), .copy("b")]), after: .copyResult, stayVisible: false)
        guard case .sequence(let items) = sequence else {
            return XCTFail("Expected .sequence passthrough, got \(sequence)")
        }
        XCTAssertEqual(items.count, 2)

        // A dismissing sequence is still wrapped by stayVisible (every item dismisses), matching
        // the plan: passthrough happens first, then the stayVisible wrap applies to dismissing results.
        let wrappedSequence = ActionResultAdapter.apply(raw: .sequence([.copy("a"), .copy("b")]), after: .copyResult, stayVisible: true)
        guard case .keepVisible(.sequence(let wrappedItems)) = wrappedSequence else {
            return XCTFail("Expected .keepVisible(.sequence) under stayVisible, got \(wrappedSequence)")
        }
        XCTAssertEqual(wrappedItems.count, 2)
    }

    // MARK: - stayVisible wraps only when the normalized result would dismiss

    func testStayVisibleWrapsDismissingResult() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .default, stayVisible: true)
        guard case .keepVisible(.copy("x")) = copy else {
            return XCTFail("Expected .keepVisible(.copy), got \(copy)")
        }

        let paste = ActionResultAdapter.apply(raw: .paste("x"), after: .default, stayVisible: true)
        guard case .keepVisible(.paste("x")) = paste else {
            return XCTFail("Expected .keepVisible(.paste), got \(paste)")
        }

        let url = URL(string: "https://example.com")!
        let openURL = ActionResultAdapter.apply(raw: .openURL(url), after: .default, stayVisible: true)
        guard case .keepVisible(.openURL(let target)) = openURL else {
            return XCTFail("Expected .keepVisible(.openURL), got \(openURL)")
        }
        XCTAssertEqual(target, url)
    }

    func testStayVisibleDoesNotWrapPresentations() {
        let status = ActionResultAdapter.apply(raw: .showStatus(StatusFeedback(message: "s", style: .info)), after: .default, stayVisible: true)
        guard case .showStatus = status else {
            return XCTFail("Expected unwrapped .showStatus, got \(status)")
        }
    }

    func testStayVisibleFalseLeavesResultUnwrapped() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .default, stayVisible: false)
        guard case .copy(let text) = copy else {
            return XCTFail("Expected .copy, got \(copy)")
        }
        XCTAssertEqual(text, "x")
    }
}