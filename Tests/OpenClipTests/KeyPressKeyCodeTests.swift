import XCTest
@testable import OpenClip

final class KeyPressKeyCodeTests: XCTestCase {
    func testPunctuationKeysResolveToANSIKeyCodes() {
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "-"), 0x1B)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "minus"), 0x1B)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "="), 0x18)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "["), 0x21)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "/"), 0x2C)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "\\"), 0x2A)
    }

    func testExistingKeysUnchanged() {
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "x"), 0x07)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "0"), 0x1D)
        XCTAssertEqual(DefaultActionResultHandler.keyCode(for: "return"), 0x24)
        XCTAssertNil(DefaultActionResultHandler.keyCode(for: "§"))
    }
}
