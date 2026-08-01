import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManifestTests: XCTestCase {
    func testDecodeManifestWithOptionsAndCamelCase() throws {
        let json = """
        {
          "id": "com.example.test",
          "name": "Test Extension",
          "options": [
            {
              "identifier": "api_key",
              "label": "API Key",
              "type": "string",
              "default": "default_val"
            }
          ],
          "actions": [
            {
              "title": "Run Script",
              "script": "main.js",
              "icon": "symbol:play"
            }
          ]
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(metadata.identifier, "com.example.test")
        XCTAssertEqual(metadata.name, "Test Extension")
        XCTAssertEqual(metadata.options?.count, 1)
        XCTAssertEqual(metadata.options?.first?.identifier, "api_key")
    }
}
