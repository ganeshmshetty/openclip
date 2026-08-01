import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManifestTests: XCTestCase {
    func testDecodeManifestWithIdKey() throws {
        let json = """
        {
          "id": "com.example.idtest",
          "name": "Test Extension with id",
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
        XCTAssertEqual(metadata.identifier, "com.example.idtest")
        XCTAssertEqual(metadata.name, "Test Extension with id")
        XCTAssertEqual(metadata.options?.count, 1)
        XCTAssertEqual(metadata.options?.first?.identifier, "api_key")
    }

    func testDecodeManifestWithIdentifierKey() throws {
        let json = """
        {
          "identifier": "com.example.identifiertest",
          "name": "Test Extension with identifier",
          "actions": [
            {
              "title": "Search Action",
              "url": "https://example.com/search?q={query}"
            }
          ]
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(metadata.identifier, "com.example.identifiertest")
        XCTAssertEqual(metadata.name, "Test Extension with identifier")
        XCTAssertEqual(metadata.actions.count, 1)
        XCTAssertEqual(metadata.actions.first?.url, "https://example.com/search?q={query}")
    }

    func testDecodeLegacyPascalCaseManifest() throws {
        let json = """
        {
          "Identifier": "com.example.legacy",
          "Name": "Legacy Extension",
          "Actions": [
            {
              "Title": "Legacy Script Action",
              "Script": "run.sh",
              "Icon": "symbol:star"
            },
            {
              "Title": "Legacy URL Action",
              "URL": "https://legacy.example.com",
              "Regular Expression": "https?://.*"
            }
          ]
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(metadata.identifier, "com.example.legacy")
        XCTAssertEqual(metadata.name, "Legacy Extension")
        XCTAssertEqual(metadata.actions.count, 2)

        let action1 = metadata.actions[0]
        XCTAssertEqual(action1.title, "Legacy Script Action")
        XCTAssertEqual(action1.script, "run.sh")
        XCTAssertEqual(action1.icon, "symbol:star")

        let action2 = metadata.actions[1]
        XCTAssertEqual(action2.title, "Legacy URL Action")
        XCTAssertEqual(action2.url, "https://legacy.example.com")
        XCTAssertEqual(action2.regex, "https?://.*")
    }

    func testDecodeOptionsWithCamelCaseAndPascalCaseFallback() throws {
        let json = """
        {
          "id": "com.example.options",
          "name": "Options Test",
          "Actions": [],
          "Options": [
            {
              "Identifier": "opt_pascal",
              "Label": "Pascal Option",
              "Type": "string",
              "Default": "val_pascal"
            },
            {
              "id": "opt_camel",
              "label": "Camel Option",
              "type": "boolean",
              "default": "true"
            }
          ]
        }
        """.data(using: .utf8)!

        let metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(metadata.identifier, "com.example.options")
        XCTAssertEqual(metadata.options?.count, 2)

        let opt1 = metadata.options?[0]
        XCTAssertEqual(opt1?.identifier, "opt_pascal")
        XCTAssertEqual(opt1?.label, "Pascal Option")
        XCTAssertEqual(opt1?.type, "string")
        XCTAssertEqual(opt1?.defaultValue, "val_pascal")

        let opt2 = metadata.options?[1]
        XCTAssertEqual(opt2?.identifier, "opt_camel")
        XCTAssertEqual(opt2?.label, "Camel Option")
        XCTAssertEqual(opt2?.type, "boolean")
        XCTAssertEqual(opt2?.defaultValue, "true")
    }
}
