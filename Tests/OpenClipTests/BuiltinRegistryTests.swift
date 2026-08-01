import XCTest
@testable import Core

@MainActor
final class BuiltinRegistryTests: XCTestCase {
    func testMakeCoreBuiltinsReturnsExpectedCount() {
        let expectedCount = 6 + 1 + TransformCase.allCases.count
        XCTAssertEqual(BuiltinRegistry.makeCoreBuiltins().count, expectedCount)
    }

    func testAllCoreBuiltinIdsAreUnique() {
        let ids = BuiltinRegistry.makeCoreBuiltins().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testExpectedIdsPresent() {
        let ids = Set(BuiltinRegistry.makeCoreBuiltins().map(\.id))
        XCTAssertTrue(ids.contains("builtin.search"))
        XCTAssertTrue(ids.contains("builtin.define"))
        XCTAssertTrue(ids.contains("builtin.copy"))
        XCTAssertTrue(ids.contains("builtin.cut"))
        XCTAssertTrue(ids.contains("builtin.paste"))
        XCTAssertTrue(ids.contains("builtin.calculate"))
        XCTAssertTrue(ids.contains("builtin.transform"))
        XCTAssertTrue(ids.contains("builtin.transform.uppercase"))
    }
}
