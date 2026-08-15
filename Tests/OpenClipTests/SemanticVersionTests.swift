import XCTest
@testable import Core

final class SemanticVersionTests: XCTestCase {
    func testParseFullVersion() {
        XCTAssertEqual(SemanticVersion.parse("1.2.3"), SemanticVersion(1, 2, 3))
    }

    func testParseToleratesShortAndPrefixedForms() {
        XCTAssertEqual(SemanticVersion.parse("1.2"), SemanticVersion(1, 2, 0))
        XCTAssertEqual(SemanticVersion.parse("1"), SemanticVersion(1, 0, 0))
        XCTAssertEqual(SemanticVersion.parse("v1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion.parse("1.2.3-beta.1"), SemanticVersion(1, 2, 3))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(SemanticVersion.parse(""))
        XCTAssertNil(SemanticVersion.parse("banana"))
        XCTAssertNil(SemanticVersion.parse("1..3"))
    }

    func testComparison() {
        XCTAssertLessThan(SemanticVersion(1, 2, 3), SemanticVersion(1, 3, 0))
        XCTAssertLessThan(SemanticVersion(1, 2, 3), SemanticVersion(2, 0, 0))
        XCTAssertLessThan(SemanticVersion(1, 2, 2), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion(1, 2, 3), SemanticVersion(1, 2, 3))
        XCTAssertGreaterThan(SemanticVersion(1, 5, 0), SemanticVersion(1, 2, 3))
    }
}