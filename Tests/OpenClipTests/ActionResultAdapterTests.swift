import XCTest
@testable import Core

final class ActionResultAdapterTests: XCTestCase {
    // MARK: - copyResult / pasteResult overrides

    func testCopyResultOverridesPasteAndCopy() {
        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .copyResult)
        if case .copy(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromPaste)")
        }

        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .copyResult)
        if case .copy(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .copy(x), got \(fromCopy)")
        }
    }

    func testPasteResultOverridesCopyAndPaste() {
        let fromCopy = ActionResultAdapter.apply(raw: .copy("x"), after: .pasteResult)
        if case .paste(let text) = fromCopy {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromCopy)")
        }

        let fromPaste = ActionResultAdapter.apply(raw: .paste("x"), after: .pasteResult)
        if case .paste(let text) = fromPaste {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected .paste(x), got \(fromPaste)")
        }
    }

    // MARK: - showResult degrades to the plain leaf result (canvas card rendering removed)

    func testShowResultDegradesToRawCopy() {
        let result = ActionResultAdapter.apply(raw: .copy("x"), after: .showResult)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "x")
    }

    func testShowResultDegradesToRawPaste() {
        let result = ActionResultAdapter.apply(raw: .paste("x"), after: .showResult)
        guard case .paste(let text) = result else {
            return XCTFail("Expected .paste, got \(result)")
        }
        XCTAssertEqual(text, "x")
    }

    // MARK: - none collapses to success

    func testNoneReturnsSuccessForAnyRaw() {
        let copy = ActionResultAdapter.apply(raw: .copy("x"), after: .none)
        guard case .success = copy else {
            return XCTFail("Expected .success, got \(copy)")
        }

        let openURL = ActionResultAdapter.apply(raw: .openURL(URL(string: "https://example.com")!), after: .none)
        guard case .success = openURL else {
            return XCTFail("Expected .success, got \(openURL)")
        }
    }

    // MARK: - default passes raw through

    func testDefaultPassesThroughRaw() {
        let url = URL(string: "https://example.com")!
        let openURL = ActionResultAdapter.apply(raw: .openURL(url), after: .default)
        guard case .openURL(let target) = openURL else {
            return XCTFail("Expected .openURL, got \(openURL)")
        }
        XCTAssertEqual(target, url)

        let cut = ActionResultAdapter.apply(raw: .cut("x"), after: .default)
        guard case .cut(let text) = cut else {
            return XCTFail("Expected .cut, got \(cut)")
        }
        XCTAssertEqual(text, "x")
    }

    // MARK: - presentations pass through untouched

    func testPresentationsPassThroughUnchanged() {
        let status = ActionResultAdapter.apply(raw: .showStatus(StatusFeedback(message: "s", style: .info)), after: .pasteResult)
        guard case .showStatus(let feedback) = status else {
            return XCTFail("Expected .showStatus passthrough, got \(status)")
        }
        XCTAssertEqual(feedback.message, "s")

        let config = ActionResultAdapter.apply(raw: .openConfiguration(ConfigurationRequest(actionID: "a")), after: .copyResult)
        guard case .openConfiguration(let request) = config else {
            return XCTFail("Expected .openConfiguration passthrough, got \(config)")
        }
        XCTAssertEqual(request.actionID, "a")

        let keyPress = ActionResultAdapter.apply(raw: .keyPress(KeyPressSpec(key: "b")), after: .copyResult)
        guard case .keyPress(let spec) = keyPress else {
            return XCTFail("Expected .keyPress passthrough, got \(keyPress)")
        }
        XCTAssertEqual(spec.key, "b")

        let shortcut = ActionResultAdapter.apply(raw: .runShortcut(name: "n", input: "i"), after: .copyResult)
        guard case .runShortcut(name: "n", input: "i") = shortcut else {
            return XCTFail("Expected .runShortcut passthrough, got \(shortcut)")
        }

        let sequence = ActionResultAdapter.apply(raw: .sequence([.copy("a"), .copy("b")]), after: .copyResult)
        guard case .sequence(let items) = sequence else {
            return XCTFail("Expected .sequence passthrough, got \(sequence)")
        }
        XCTAssertEqual(items.count, 2)
    }
}