import XCTest
import Core

final class TextDiffTests: XCTestCase {

    private func rendered(_ segments: [TextDiffSegment], kind: TextDiffSegment.Kind) -> String {
        segments.filter { $0.kind == kind }.map(\.text).joined()
    }

    /// The old text must be reconstructible from equal+delete and the new one from equal+insert —
    /// the property that makes the card's rendering honest.
    private func assertRoundTrip(_ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) {
        let segments = TextDiff.segments(from: old, to: new)
        let reconstructedOld = segments.filter { $0.kind != .insert }.map(\.text).joined()
        let reconstructedNew = segments.filter { $0.kind != .delete }.map(\.text).joined()
        XCTAssertEqual(reconstructedOld, old, "delete+equal must rebuild the original", file: file, line: line)
        XCTAssertEqual(reconstructedNew, new, "insert+equal must rebuild the result", file: file, line: line)
    }

    func testIdenticalTextIsOneEqualSegment() {
        let segments = TextDiff.segments(from: "hey how are you", to: "hey how are you")
        XCTAssertEqual(segments, [TextDiffSegment(kind: .equal, text: "hey how are you")])
        XCTAssertEqual(TextDiff.equalRatio(of: segments), 1.0)
    }

    func testEmptyInputs() {
        XCTAssertEqual(TextDiff.segments(from: "", to: ""), [])
        XCTAssertEqual(TextDiff.segments(from: "", to: "added"), [TextDiffSegment(kind: .insert, text: "added")])
        XCTAssertEqual(TextDiff.segments(from: "gone", to: ""), [TextDiffSegment(kind: .delete, text: "gone")])
    }

    /// The proofread case from the card: capitalization + punctuation edits show as small
    /// insert/delete runs inside a mostly-equal body.
    func testProofreadEditProducesCharacterLevelRuns() {
        let old = "hey how are you doing"
        let new = "Hey, how are you doing?"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), "h")
        XCTAssertEqual(rendered(segments, kind: .insert), "H,?")
        XCTAssertGreaterThan(TextDiff.equalRatio(of: segments), 0.8,
                             "a light edit must read as mostly-equal so the card opens on the diff")
    }

    func testPureInsertionAndDeletionKeepSurroundingTextEqual() {
        let inserted = TextDiff.segments(from: "the cat sat", to: "the black cat sat")
        assertRoundTrip("the cat sat", "the black cat sat")
        XCTAssertEqual(rendered(inserted, kind: .insert), "black ")
        XCTAssertTrue(inserted.allSatisfy { $0.kind != .delete })

        let deleted = TextDiff.segments(from: "the black cat sat", to: "the cat sat")
        assertRoundTrip("the black cat sat", "the cat sat")
        XCTAssertEqual(rendered(deleted, kind: .delete), "black ")
        XCTAssertTrue(deleted.allSatisfy { $0.kind != .insert })
    }

    func testSegmentsAreCoalescedNotPerCharacter() {
        let segments = TextDiff.segments(from: "abcdef", to: "abXYZdef")
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .equal, text: "ab"),
            TextDiffSegment(kind: .delete, text: "c"),
            TextDiffSegment(kind: .insert, text: "XYZ"),
            TextDiffSegment(kind: .equal, text: "def")
        ])
    }

    func testGraphemeClustersAreNeverSplit() {
        let old = "ship it 🙂"
        let new = "ship it 👍🏽"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), "🙂")
        XCTAssertEqual(rendered(segments, kind: .insert), "👍🏽")
    }

    func testUnrelatedRewriteFallsBackToWholesaleReplacement() {
        // Far beyond `maxEditDistance`: the honest answer is "this was replaced", not a shredded
        // character salad — and it must still round-trip.
        let old = String(repeating: "a", count: 1_200)
        let new = String(repeating: "b", count: 1_200)
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.kind, .delete)
        XCTAssertEqual(segments.last?.kind, .insert)
        XCTAssertEqual(TextDiff.equalRatio(of: segments), 0.0)
    }

    func testLongTextWithSmallEditStillDiffsThroughPrefixSuffixTrim() {
        let filler = String(repeating: "lorem ipsum dolor sit amet. ", count: 400) // ~11k chars
        let old = filler + "teh end"
        let new = filler + "the end"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertGreaterThan(TextDiff.equalRatio(of: segments), 0.99,
                             "prefix/suffix trimming must keep a long text diffable")
        XCTAssertLessThanOrEqual(rendered(segments, kind: .delete).count, 3)
    }

    func testOversizedComparisonStaysBounded() {
        let old = String(repeating: "x", count: 20_000)
        let new = String(repeating: "y", count: 20_000)
        let started = Date()
        let segments = TextDiff.segments(from: old, to: new)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "the length budget must short-circuit")
        assertRoundTrip(old, new)
        XCTAssertEqual(segments.count, 2)
    }

    func testEqualRatioSeparatesEditsFromRewrites() {
        let edit = TextDiff.segments(from: "hey how are you doing", to: "Hey, how are you doing?")
        let rewrite = TextDiff.segments(from: "hey how are you doing", to: "Bonjour, comment allez-vous ?")
        XCTAssertGreaterThanOrEqual(TextDiff.equalRatio(of: edit), 0.5)
        XCTAssertLessThan(TextDiff.equalRatio(of: rewrite), 0.5)
    }

    func testIsMeaningfulEdit() {
        // Proofread / grammar fix
        XCTAssertTrue(TextDiff.isMeaningfulEdit(from: "hey how are you doing", to: "Hey, how are you doing?"))
        XCTAssertTrue(TextDiff.isMeaningfulEdit(from: "I has an apple", to: "I have an apple"))

        // Translation -> false
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "hey how are you doing", to: "Bonjour, comment allez-vous ?"))

        // Explanation / completely different -> false
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "quantum computing", to: "Quantum computing is a multidisciplinary field comprising aspects of computer science, physics, and mathematics."))

        // Summarize / condensation -> false
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "OpenClip is a macOS utility for quick actions. It helps you interact with text anywhere.", to: "Summary: A Mac text utility."))

        // Identical text -> false (no change)
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "hello world", to: "hello world"))

        // Empty text -> false
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "", to: "something"))

        // Massive text (> 2,500 chars) -> false
        let huge = String(repeating: "word ", count: 700)
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: huge, to: huge + "!"))
    }

    func testWhitespaceOnlyChangesAreNotMeaningfulEdits() {
        XCTAssertTrue(TextDiff.differsOnlyInWhitespace(from: "one\ntwo\n\nthree", to: "one two three"))
        XCTAssertTrue(TextDiff.differsOnlyInWhitespace(from: "one   two", to: "one two"))
        XCTAssertFalse(TextDiff.isMeaningfulEdit(from: "one\ntwo\n\nthree", to: "one two three"),
                       "line-break removal must not open a diff that repaints the old line structure")

        XCTAssertFalse(TextDiff.differsOnlyInWhitespace(from: "one\ntwo", to: "One two"))
        XCTAssertFalse(TextDiff.differsOnlyInWhitespace(from: "same", to: "same"),
                       "identical text is not a whitespace-only edit")
    }

    func testWordReplacementDoesNotFragmentCommonLetters() {
        let oldCat = "the large cat"
        let newCat = "the huge cat"
        let catSegments = TextDiff.segments(from: oldCat, to: newCat)
        assertRoundTrip(oldCat, newCat)
        XCTAssertEqual(catSegments, [
            TextDiffSegment(kind: .equal, text: "the "),
            TextDiffSegment(kind: .delete, text: "large"),
            TextDiffSegment(kind: .insert, text: "huge"),
            TextDiffSegment(kind: .equal, text: " cat")
        ], "unrelated words sharing letters (like 'ge' in large/huge) must not be fragmented")

        let oldPie = "the apple pie"
        let newPie = "the orange pie"
        let pieSegments = TextDiff.segments(from: oldPie, to: newPie)
        assertRoundTrip(oldPie, newPie)
        XCTAssertEqual(pieSegments, [
            TextDiffSegment(kind: .equal, text: "the "),
            TextDiffSegment(kind: .delete, text: "apple"),
            TextDiffSegment(kind: .insert, text: "orange"),
            TextDiffSegment(kind: .equal, text: " pie")
        ], "suffix trimming must respect token boundaries and not match 'e pie'")
    }

    func testPhraseReplacementDoesNotFragment() {
        let old = "we met in the morning yesterday"
        let new = "we met at dawn yesterday"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .equal, text: "we met "),
            TextDiffSegment(kind: .delete, text: "in the morning"),
            TextDiffSegment(kind: .insert, text: "at dawn"),
            TextDiffSegment(kind: .equal, text: " yesterday")
        ])
    }

    func testTypoInWordRefinesToCharacterDiff() {
        let old = "this is definately better"
        let new = "this is definitely better"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), "a")
        XCTAssertEqual(rendered(segments, kind: .insert), "i")
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .equal, text: "this is defin"),
            TextDiffSegment(kind: .delete, text: "a"),
            TextDiffSegment(kind: .insert, text: "i"),
            TextDiffSegment(kind: .equal, text: "tely better")
        ])
    }

    func testCaseChangeRefinesToCharacterDiff() {
        let old = "monday morning"
        let new = "Monday morning"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), "m")
        XCTAssertEqual(rendered(segments, kind: .insert), "M")
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .delete, text: "m"),
            TextDiffSegment(kind: .insert, text: "M"),
            TextDiffSegment(kind: .equal, text: "onday morning")
        ])
    }

    func testPunctuationChangeProducesCleanTokenDiff() {
        let old = "hello world."
        let new = "hello world!"
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), ".")
        XCTAssertEqual(rendered(segments, kind: .insert), "!")
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .equal, text: "hello world"),
            TextDiffSegment(kind: .delete, text: "."),
            TextDiffSegment(kind: .insert, text: "!"),
        ])
    }

    func testTokenizeRoundTrip() {
        let samples = [
            "hello world",
            "Hey, how are you doing?",
            "multiple   spaces and \n newlines\t",
            "ship it 👍🏽 with 123 emojis 🙂!",
            "don't count on it; it's complicated.",
            "",
            "single",
            "   "
        ]
        for sample in samples {
            XCTAssertEqual(TextDiff.tokenize(sample).joined(), sample, "tokenization must preserve 100% round-trip fidelity")
        }
    }

    func testMultipleTyposInSentenceRefinesAndIsMeaningfulEdit() {
        let old = "I will definately accomodate your request tomorrow."
        let new = "I will definitely accommodate your request tomorrow."
        XCTAssertTrue(TextDiff.isMeaningfulEdit(from: old, to: new), "Proofread sentence with typos must be a meaningful edit")
        let segments = TextDiff.segments(from: old, to: new)
        assertRoundTrip(old, new)
        XCTAssertEqual(rendered(segments, kind: .delete), "a")
        XCTAssertEqual(rendered(segments, kind: .insert), "im")
        XCTAssertEqual(segments, [
            TextDiffSegment(kind: .equal, text: "I will defin"),
            TextDiffSegment(kind: .delete, text: "a"),
            TextDiffSegment(kind: .insert, text: "i"),
            TextDiffSegment(kind: .equal, text: "tely accom"),
            TextDiffSegment(kind: .insert, text: "m"),
            TextDiffSegment(kind: .equal, text: "odate your request tomorrow.")
        ])
    }
}
