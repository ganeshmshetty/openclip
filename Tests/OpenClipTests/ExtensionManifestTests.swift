import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionManifestTests: XCTestCase {
    func testExtensionActionKindNormalization() {
        XCTAssertEqual(ExtensionActionKind(rawType: "url"), .url)
        XCTAssertEqual(ExtensionActionKind(rawType: "js"), .js)
        XCTAssertEqual(ExtensionActionKind(rawType: "canvas"), .url, "canvas was removed with the canvas feature; unknown kinds fall back to .url")
        XCTAssertFalse(ExtensionActionKind.isRecognized(rawType: "canvas"), "canvas kind must be rejected at validation")
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

    func testRulesRelevantMetadataDecodesTogether() throws {
        let json = """
        {
            "id": "copy",
            "title": "Copy",
            "type": "url",
            "url": "https://example.com",
            "regex": "^[a-z]+$",
            "requirements": {
                "apps": ["com.allowed"],
                "apps-mode": "allow"
            }
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.regex, "^[a-z]+$")
        XCTAssertEqual(action.requirements?.apps, ["com.allowed"])
        XCTAssertEqual(action.requirements?.appsMode, .allow)
    }

    func testMenuRelevanceDecodes() throws {
        let json = """
        {
            "id": "slug",
            "title": "Slugify",
            "type": "shell",
            "script": "slug.sh",
            "menuRelevance": "\\\\s"
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.menuRelevance, "\\s")

        let absent = try JSONDecoder().decode(ExtensionActionMetadata.self, from: #"{"title":"Plain"}"#.data(using: .utf8)!)
        XCTAssertNil(absent.menuRelevance)
    }

    func testActionDecodesLoadingKey() throws {
        let json = """
        {
          "identifier": "com.test.music",
          "name": "Music",
          "action": {
            "title": "Music",
            "type": "applescript",
            "script": "main.applescript",
            "loading": true,
            "loadingMessage": "Connecting to Music…"
          }
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        XCTAssertEqual(manifest.actions.first?.loading, true)
        XCTAssertEqual(manifest.actions.first?.loadingMessage, "Connecting to Music…")
    }

    func testLoadingMessageDefaultsNil() throws {
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self,
                                             from: #"{"title":"Plain"}"#.data(using: .utf8)!)
        XCTAssertNil(action.loadingMessage)
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
        XCTAssertEqual(manifest.version, "1.0.0")
    }

    func testSecondaryToastAndSecondaryDecode() throws {
        let json = """
        {
            "id": "clip",
            "title": "Clip",
            "type": "url",
            "url": "https://example.com",
            "secondary": {
                "type": "copy",
                "value": "{{query}}"
            },
            "toast": {
                "message": "Copied",
                "style": "success"
            },
            "secondaryToast": {
                "message": "Copied (secondary)",
                "style": "info"
            }
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.secondary?.type, "copy")
        XCTAssertEqual(action.secondary?.value, "{{query}}")
        XCTAssertNil(action.secondary?.message)
        XCTAssertEqual(action.toast?.message, "Copied")
        XCTAssertEqual(action.toast?.style, "success")
        XCTAssertEqual(action.secondaryToast?.message, "Copied (secondary)")
        XCTAssertEqual(action.secondaryToast?.style, "info")
    }

    func testSecondaryToastDecodesWithDashAlias() throws {
        let json = """
        {
            "id": "clip",
            "type": "url",
            "url": "https://example.com",
            "secondary-toast": {
                "message": "Copied",
                "style": "info"
            }
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.secondaryToast?.message, "Copied")
        XCTAssertEqual(action.secondaryToast?.style, "info")
    }

    func testSecondaryDecodesOnNonJavascriptKinds() throws {
        for kind in ["url", "shell", "applescript", "shortcut"] {
            let json = """
            {
                "id": "a-\(kind)",
                "type": "\(kind)",
                "url": "https://example.com",
                "secondary": { "type": "copy" }
            }
            """.data(using: .utf8)!
            let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
            XCTAssertNotNil(action.secondary, "secondary should decode on kind \(kind)")
            XCTAssertEqual(action.secondary?.type, "copy")
        }
    }

    func testSecondaryDecodesUnconditionallyOnJavascriptKind() throws {
        let json = """
        {
            "id": "jsact",
            "type": "javascript",
            "scriptCode": "return 1;",
            "secondary": { "type": "copy", "value": "x" }
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.secondary?.type, "copy", "decode carries secondary on any kind; the validator enforces kind-scoping")
    }

    func testToastDefaultsNilStyle() throws {
        let json = """
        {
            "id": "clip",
            "type": "url",
            "url": "https://example.com",
            "toast": { "message": "Done" }
        }
        """.data(using: .utf8)!
        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertEqual(action.toast?.message, "Done")
        XCTAssertNil(action.toast?.style)
    }

    func testEditActionSheetPreservesVersionAndCapabilities() throws {
        let manifest = ExtensionMetadata(
            identifier: "com.test.extension",
            name: "Test Ext",
            actions: [ExtensionActionMetadata(id: "act1", title: "Act 1", url: "https://example.com", type: "url")],
            version: "2.1.0",
            capabilities: ["fetch"]
        )

        let updatedManifest = ExtensionMetadata(
            identifier: manifest.identifier,
            name: manifest.name,
            actions: manifest.actions,
            options: manifest.options,
            version: manifest.version,
            capabilities: manifest.capabilities
        )

        XCTAssertEqual(updatedManifest.version, "2.1.0")
        XCTAssertEqual(updatedManifest.capabilities, ["fetch"])
    }

    func testManifestRequiresName() throws {
        let jsonWithoutName = """
        {
          "identifier": "com.example.noname",
          "actions": []
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionMetadata.self, from: jsonWithoutName)) { error in
            guard case DecodingError.keyNotFound = error else {
                XCTFail("Expected DecodingError.keyNotFound but got \(error)")
                return
            }
        }
    }

    func testOptionRequiresLabel() throws {
        let jsonWithoutLabel = """
        {
          "identifier": "opt1",
          "type": "string"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionOptionMetadata.self, from: jsonWithoutLabel)) { error in
            guard case DecodingError.keyNotFound = error else {
                XCTFail("Expected DecodingError.keyNotFound but got \(error)")
                return
            }
        }
    }

    func testToastRequiresMessage() throws {
        let jsonWithoutMessage = """
        {
          "style": "success"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ExtensionToastDeclaration.self, from: jsonWithoutMessage)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                XCTFail("Expected DecodingError.keyNotFound but got \(error)")
                return
            }
            XCTAssertEqual(key.stringValue, "message")
        }
    }
}

