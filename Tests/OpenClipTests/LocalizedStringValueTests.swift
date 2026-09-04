import XCTest
@testable import Core

final class LocalizedStringValueTests: XCTestCase {
    func testDecodeFromStringLiteral() throws {
        let json = "\"Hello World\"".data(using: .utf8)!
        let val = try JSONDecoder().decode(LocalizedStringValue.self, from: json)
        XCTAssertEqual(val.values["default"], "Hello World")
        XCTAssertEqual(val.resolve(), "Hello World")
    }

    func testDecodeFromDictionary() throws {
        let json = "{\"en\": \"Hello\", \"fr\": \"Bonjour\", \"zh-Hans\": \"你好\"}".data(using: .utf8)!
        let val = try JSONDecoder().decode(LocalizedStringValue.self, from: json)
        XCTAssertEqual(val.values["fr"], "Bonjour")
        XCTAssertEqual(val.values["zh-Hans"], "你好")
    }

    func testDecodeInvalidTypeThrowsDataCorrupted() {
        let invalidJson = "123".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(LocalizedStringValue.self, from: invalidJson)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted but got \(error)")
                return
            }
        }

        let arrayJson = "[\"a\", \"b\"]".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(LocalizedStringValue.self, from: arrayJson)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted but got \(error)")
                return
            }
        }
    }

    func testResolveHierarchy() {
        let val = LocalizedStringValue(dictionary: [
            "en": "English",
            "zh-Hans": "Simplified Chinese",
            "zh-Hant": "Traditional Chinese",
            "fr": "French"
        ])
        XCTAssertEqual(val.resolve(for: Locale(identifier: "fr_FR")), "French")
        XCTAssertEqual(val.resolve(for: Locale(identifier: "zh-Hans")), "Simplified Chinese")
        XCTAssertEqual(val.resolve(for: Locale(identifier: "zh_Hant_TW")), "Traditional Chinese")
        XCTAssertEqual(val.resolve(for: Locale(identifier: "de_DE")), "English")
    }
}
