import XCTest
@testable import Core

final class TransformRelevanceTests: XCTestCase {

    func testCaseConversionsRelevantForWords() {
        XCTAssertTrue(TransformCase.uppercase.isRelevant(for: "hello world"))
        XCTAssertTrue(TransformCase.lowercase.isRelevant(for: "HELLO WORLD"))
        XCTAssertTrue(TransformCase.camelCase.isRelevant(for: "Hello World"))
        XCTAssertFalse(TransformCase.uppercase.isRelevant(for: "!!!???"))
        XCTAssertFalse(TransformCase.camelCase.isRelevant(for: "   "))
    }

    func testNoOpTransformsAreHidden() {
        XCTAssertFalse(TransformCase.uppercase.isRelevant(for: "HELLO"), "Already uppercase: no-op")
        XCTAssertFalse(TransformCase.lowercase.isRelevant(for: "hello"), "Already lowercase: no-op")
        XCTAssertFalse(TransformCase.titleCase.isRelevant(for: "Hello World"), "Already title case: no-op")
        XCTAssertFalse(TransformCase.camelCase.isRelevant(for: "hello"), "Single lowercase word: no-op")
    }
}
