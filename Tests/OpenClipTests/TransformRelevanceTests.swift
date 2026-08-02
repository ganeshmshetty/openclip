import XCTest
@testable import Core

final class TransformRelevanceTests: XCTestCase {

    func testCaseConversionsRelevantForWords() {
        XCTAssertTrue(TransformCase.uppercase.isRelevant(for: "hello world"))
        XCTAssertTrue(TransformCase.lowercase.isRelevant(for: "HELLO WORLD"))
        XCTAssertTrue(TransformCase.camelCase.isRelevant(for: "Hello World"))
        XCTAssertFalse(TransformCase.uppercase.isRelevant(for: "!!!???"))
        XCTAssertFalse(TransformCase.pascalCase.isRelevant(for: "   "))
    }

    func testTrimWhitespaceOnlyWhenNeeded() {
        XCTAssertTrue(TransformCase.trimWhitespace.isRelevant(for: "  hello  "))
        XCTAssertFalse(TransformCase.trimWhitespace.isRelevant(for: "hello"))
    }

    func testLineToolsRelevantForMultiLine() {
        XCTAssertTrue(TransformCase.sortLines.isRelevant(for: "banana\napple"))
        XCTAssertTrue(TransformCase.removeDuplicates.isRelevant(for: "a\na"))
        XCTAssertFalse(TransformCase.sortLines.isRelevant(for: "single line"))
    }

    func testReverseTextRelevantForAnyText() {
        XCTAssertTrue(TransformCase.reverseText.isRelevant(for: "hello"))
        XCTAssertFalse(TransformCase.reverseText.isRelevant(for: ""))
    }

    func testURLEncodingRelevance() {
        XCTAssertTrue(TransformCase.urlEncode.isRelevant(for: "hello world"))
        XCTAssertFalse(TransformCase.urlEncode.isRelevant(for: "hello-world-123"))
        XCTAssertTrue(TransformCase.urlDecode.isRelevant(for: "hello%20world"))
        XCTAssertFalse(TransformCase.urlDecode.isRelevant(for: "hello world"))
    }

    func testURLDecodeRelevanceRejectsInvalidPercentEscapes() {
        XCTAssertFalse(TransformCase.urlDecode.isRelevant(for: "%"))
        XCTAssertFalse(TransformCase.urlDecode.isRelevant(for: "%ZZ"))
        XCTAssertFalse(TransformCase.urlDecode.isRelevant(for: "100%"))
    }

    func testBase64Relevance() {
        XCTAssertTrue(TransformCase.base64Decode.isRelevant(for: "aGVsbG8="))
        XCTAssertFalse(TransformCase.base64Decode.isRelevant(for: "hello world!!"))
        XCTAssertTrue(TransformCase.base64Encode.isRelevant(for: "hello"))
        XCTAssertFalse(TransformCase.base64Encode.isRelevant(for: ""))
    }

    func testBase64DecodeRelevanceRejectsInvalidInputs() {
        XCTAssertFalse(TransformCase.base64Decode.isRelevant(for: "A"), "Single non-padded character isn't decodable")
        XCTAssertFalse(TransformCase.base64Decode.isRelevant(for: "0w=="), "0x0xD3 alone is not valid UTF-8")
        XCTAssertFalse(TransformCase.base64Decode.isRelevant(for: "hello world!!"))
    }

    func testJSONRelevance() {
        XCTAssertTrue(TransformCase.formatJSON.isRelevant(for: "{\"name\":\"openclip\"}"))
        XCTAssertFalse(TransformCase.formatJSON.isRelevant(for: "just plain text"))
    }

    func testNoOpTransformsAreHidden() {
        XCTAssertFalse(TransformCase.uppercase.isRelevant(for: "HELLO"), "Already uppercase: no-op")
        XCTAssertFalse(TransformCase.lowercase.isRelevant(for: "hello"), "Already lowercase: no-op")
        XCTAssertFalse(TransformCase.titleCase.isRelevant(for: "Hello World"), "Already title case: no-op")
        XCTAssertFalse(TransformCase.camelCase.isRelevant(for: "hello"), "Single lowercase word: no-op")
        XCTAssertFalse(TransformCase.pascalCase.isRelevant(for: "Hello"), "Single capitalized word: no-op")
        XCTAssertFalse(TransformCase.sortLines.isRelevant(for: "apple\nbanana"), "Already sorted: no-op")
        XCTAssertFalse(TransformCase.removeDuplicates.isRelevant(for: "a\nb\nc"), "No duplicate lines: no-op")
        XCTAssertFalse(TransformCase.reverseText.isRelevant(for: "racecar"), "Palindrome: no-op")
        XCTAssertFalse(TransformCase.urlEncode.isRelevant(for: "hello-world"), "No unsafe characters: no-op")
        let prettyJSON = try! JSONSerialization.data(
            withJSONObject: ["name": "openclip"], options: [.prettyPrinted]
        )
        XCTAssertFalse(
            TransformCase.formatJSON.isRelevant(for: String(data: prettyJSON, encoding: .utf8)!),
            "Already pretty-printed: no-op"
        )
    }
}
