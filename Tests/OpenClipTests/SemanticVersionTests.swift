import XCTest
@testable import Core

final class SemanticVersionTests: XCTestCase {
    func testParseFullVersion() {
        XCTAssertEqual(SemanticVersion.parse("1.2.3"), SemanticVersion(1, 2, 3))
    }

    func testParseToleratesPrefixedForms() {
        XCTAssertEqual(SemanticVersion.parse("v1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion.parse("V1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion.parse("1.2.3-beta.1"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion.parse("  1.2.3  "), SemanticVersion(1, 2, 3))
    }

    func testParseRejectsShortTriplets() {
        XCTAssertNil(SemanticVersion.parse("1"))
        XCTAssertNil(SemanticVersion.parse("1.2"))
        XCTAssertNil(SemanticVersion.parse("1.2.3.4"))
        XCTAssertNil(SemanticVersion.parse("1.2.3."))
        XCTAssertNil(SemanticVersion.parse("v1.2"))
    }

    func testStringInitializer() {
        XCTAssertEqual(SemanticVersion(string: "2.1.0"), SemanticVersion(2, 1, 0))
        XCTAssertNil(SemanticVersion(string: "banana"))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(SemanticVersion.parse(""))
        XCTAssertNil(SemanticVersion.parse("banana"))
        XCTAssertNil(SemanticVersion.parse("1..3"))
        XCTAssertNil(SemanticVersion.parse(".1.2"))
        XCTAssertNil(SemanticVersion.parse("1.2.x"))
    }

    func testParseRejectsNonASCIIAndOverflow() {
        XCTAssertNil(SemanticVersion.parse("1.2.٣"))
        XCTAssertNil(SemanticVersion.parse("١.2.3"))
        XCTAssertNil(SemanticVersion.parse("1.2.99999999999999999999"))
        XCTAssertNil(SemanticVersion.parse("99999999999999999999.0.0"))
        XCTAssertNil(SemanticVersion.parse("-1.0.0"))
        XCTAssertNil(SemanticVersion.parse("+1.0.0"))
    }

    func testParseAcceptsLargeButInRangeComponents() {
        XCTAssertEqual(SemanticVersion.parse("9223372036854775807.0.0"), SemanticVersion(Int.max, 0, 0))
    }

    func testComparison() {
        XCTAssertLessThan(SemanticVersion(1, 2, 3), SemanticVersion(1, 3, 0))
        XCTAssertLessThan(SemanticVersion(1, 2, 3), SemanticVersion(2, 0, 0))
        XCTAssertLessThan(SemanticVersion(1, 2, 2), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion(1, 2, 3), SemanticVersion(1, 2, 3))
        XCTAssertGreaterThan(SemanticVersion(1, 5, 0), SemanticVersion(1, 2, 3))
    }
}