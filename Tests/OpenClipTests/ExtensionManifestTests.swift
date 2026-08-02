import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionManifestTests: XCTestCase {
    func testExtensionActionKindNormalization() {
        XCTAssertEqual(ExtensionActionKind(rawType: "url"), .url)
        XCTAssertEqual(ExtensionActionKind(rawType: "js"), .js)
        XCTAssertEqual(ExtensionActionKind(rawType: "applescript"), .applescript)
        XCTAssertEqual(ExtensionActionKind(rawType: "shellInline"), .shellInline)
        XCTAssertEqual(ExtensionActionKind(rawType: "scriptFile"), .scriptFile)
    }

    func testManifestDecoding() throws {
        let json = """
        {
          "identifier": "com.example.translator",
          "name": "Translator",
          "version": "1.0.0",
          "actions": [
            {
              "id": "action.translate",
              "title": "Translate",
              "type": "url",
              "url": "https://translate.google.com/?text={query}"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: json)
        XCTAssertEqual(manifest.identifier, "com.example.translator")
        XCTAssertEqual(manifest.actions.count, 1)
        XCTAssertEqual(manifest.actions[0].kind, .url)
    }
}
