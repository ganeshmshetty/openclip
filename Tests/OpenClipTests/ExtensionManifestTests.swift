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
        XCTAssertEqual(ExtensionActionKind(rawType: "textSnippet"), .textSnippet)
        XCTAssertEqual(ExtensionActionKind(rawType: "textsnippet"), .textSnippet)
        XCTAssertEqual(ExtensionActionKind(rawType: "snippet"), .textSnippet)
        XCTAssertEqual(ExtensionActionKind(rawType: "text"), .textSnippet)
        XCTAssertEqual(ExtensionActionKind(rawType: "webSearch"), .webSearch)
        XCTAssertEqual(ExtensionActionKind(rawType: "websearch"), .webSearch)
        XCTAssertEqual(ExtensionActionKind(rawType: "web"), .webSearch)
        XCTAssertEqual(ExtensionActionKind(rawType: "search"), .webSearch)
        XCTAssertEqual(ExtensionActionKind(rawType: "keyPress"), .keyPress)
        XCTAssertEqual(ExtensionActionKind(rawType: "keypress"), .keyPress)
        XCTAssertEqual(ExtensionActionKind(rawType: "service"), .service)
        XCTAssertEqual(ExtensionActionKind(rawType: "shortcut"), .shortcut)
        XCTAssertEqual(ExtensionActionKind(rawType: "group"), .group)
    }

    func testRequirementsDecodeWithDashFallbackKeys() throws {
        let json = """
        {
            "regex": "^[a-z]+$",
            "regex-negated": true,
            "apps": ["Safari", "Chrome"],
            "apps-mode": "deny",
            "requires-selection": true,
            "required-options": ["prefix", "suffix"]
        }
        """.data(using: .utf8)!
        let requirements = try JSONDecoder().decode(ActionRequirements.self, from: json)
        XCTAssertEqual(requirements.regex, "^[a-z]+$")
        XCTAssertTrue(requirements.regexNegated)
        XCTAssertEqual(requirements.apps, ["Safari", "Chrome"])
        XCTAssertEqual(requirements.appsMode, .deny)
        XCTAssertTrue(requirements.requiresSelection)
        XCTAssertEqual(requirements.requiredOptions, ["prefix", "suffix"])
    }

    func testAfterAndStayVisibleDecode() throws {
        let json = """
        {
            "id": "copy",
            "title": "Copy",
            "type": "url",
            "url": "https://example.com",
            "after": "paste-result",
            "stay-visible": true
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.after, .pasteResult)
        XCTAssertEqual(action.stayVisible, true)
        XCTAssertEqual(action.requirements, nil)
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
