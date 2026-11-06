import XCTest
@testable import Core

final class SmartCopyPasteTests: XCTestCase {
    private func leftover(_ text: String, cutting word: String) -> String? {
        let ns = text as NSString
        let selection = ns.range(of: word)
        guard let range = SmartCopyPaste.smartDeleteRange(in: text, selection: selection) else { return nil }
        return ns.replacingCharacters(in: range, with: "")
    }

    func testMiddleWordTakesTrailingSpace() {
        XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: "one two three", selection: NSRange(location: 4, length: 3)),
                       NSRange(location: 4, length: 4))
        XCTAssertEqual(leftover("one two three", cutting: "two"), "one three")
    }

    func testFirstWordTakesTrailingSpace() {
        XCTAssertEqual(leftover("one two three", cutting: "one"), "two three")
    }

    func testLastWordTakesLeadingSpace() {
        XCTAssertEqual(leftover("one two three", cutting: "three"), "one two")
        XCTAssertEqual(leftover("one two three.", cutting: "three"), "one two.")
    }

    func testMidWordIsNotExtended() {
        let sel = NSRange(location: 1, length: 3)
        XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: "Hello", selection: sel), sel)
    }

    func testSelectionAlreadyIncludingSpaceIsNotExtended() {
        let text = "one two three"
        for sel in [NSRange(location: 3, length: 4), NSRange(location: 4, length: 4)] {
            XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: text, selection: sel), sel)
        }
    }

    func testNewlinesAreParagraphBoundaries() {
        XCTAssertEqual(leftover("a\none two\nb", cutting: "one"), "a\ntwo\nb")
        XCTAssertEqual(leftover("a\none two\nb", cutting: "two"), "a\none\nb")
        let sel = NSRange(location: 2, length: 3)
        XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: "a\none\nb", selection: sel), sel)
    }

    func testWholeTextIsNotExtended() {
        let sel = NSRange(location: 0, length: 4)
        XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: "word", selection: sel), sel)
    }

    func testTabAndNonBreakingSpaceCountAsSpace() {
        XCTAssertEqual(leftover("one\ttwo\tthree", cutting: "two"), "one\tthree")
        XCTAssertEqual(leftover("one\u{00A0}two", cutting: "two"), "one")
    }

    func testEmojiUsesUTF16Offsets() {
        XCTAssertEqual(leftover("😀 two three", cutting: "two"), "😀 three")
    }

    func testEmptyAndInvalidRanges() {
        let empty = NSRange(location: 2, length: 0)
        XCTAssertEqual(SmartCopyPaste.smartDeleteRange(in: "one", selection: empty), empty)
        XCTAssertNil(SmartCopyPaste.smartDeleteRange(in: "one", selection: NSRange(location: 2, length: 5)))
        XCTAssertNil(SmartCopyPaste.smartDeleteRange(in: "one", selection: NSRange(location: NSNotFound, length: 0)))
    }
}

final class SmartInsertTests: XCTestCase {
    private func insert(_ text: String, into value: String, at location: Int, length: Int = 0) -> String? {
        SmartCopyPaste.smartInsertText(text, into: value, selection: NSRange(location: location, length: length))
    }

    func testPastingAtStartOfWordAddsTrailingSpace() {
        XCTAssertEqual(insert("Computer", into: "Apple", at: 0), "Computer ")
    }

    func testPastingAtEndOfWordAddsLeadingSpace() {
        XCTAssertEqual(insert("Computer", into: "Apple", at: 5), " Computer")
    }

    func testExistingSpacesAreNotDoubled() {
        XCTAssertEqual(insert("two", into: "one  three", at: 4), "two")
        XCTAssertEqual(insert("two", into: "one ", at: 4), "two")
        XCTAssertEqual(insert("two", into: " three", at: 0), "two")
    }

    func testBetweenTwoWordsAddsBoth() {
        XCTAssertEqual(insert("two", into: "onethree", at: 3), " two ")
    }

    func testEmptyFieldAndPunctuationNeighbours() {
        XCTAssertEqual(insert("word", into: "", at: 0), "word")
        XCTAssertEqual(insert("word", into: "(.)", at: 1), "word")
    }

    func testTextWithOwnEdgeWhitespaceIsLeftAlone() {
        XCTAssertEqual(insert(" word", into: "Apple", at: 5), " word")
    }

    func testInvalidRange() {
        XCTAssertNil(insert("word", into: "Apple", at: 9))
    }
}
