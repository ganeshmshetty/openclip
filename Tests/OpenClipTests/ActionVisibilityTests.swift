import XCTest
@testable import Core

private extension ActionContext {
    init(selectedText: String, bundleID: String? = "com.test.app", source: SelectionSource = .selection) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: bundleID, localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default,
            source: source
        )
        self.init(selection: selection, modifiers: [])
    }
}

@MainActor
final class ActionVisibilityTests: XCTestCase {
    // MARK: - App allow / deny lists

    func testAllowListEnablesWhenBundleIdentifierMatches() {
        let requirements = ActionRequirements(apps: ["com.test.app"], appsMode: .allow)
        let context = ActionContext(selectedText: "hello", bundleID: "com.test.app")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    func testAllowListDisablesWhenBundleIdentifierDoesNotMatch() {
        let requirements = ActionRequirements(apps: ["com.other.app"], appsMode: .allow)
        let context = ActionContext(selectedText: "hello", bundleID: "com.test.app")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testDenyListDisablesWhenBundleIdentifierMatches() {
        let requirements = ActionRequirements(apps: ["com.test.app"], appsMode: .deny)
        let context = ActionContext(selectedText: "hello", bundleID: "com.test.app")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testDenyListEnablesWhenBundleIdentifierDoesNotMatch() {
        let requirements = ActionRequirements(apps: ["com.other.app"], appsMode: .deny)
        let context = ActionContext(selectedText: "hello", bundleID: "com.test.app")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    // MARK: - requiresSelection

    func testEmptySelectionDisabledByDefault() {
        let context = ActionContext(selectedText: "   ")
        let result = ActionVisibility.isEnabled(requirements: nil, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testRequiresSelectionFalseAllowsEmptyText() {
        let requirements = ActionRequirements(requiresSelection: false)
        let context = ActionContext(selectedText: "")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    func testDecodedRequirementsWithoutSelectionKeyDefaultToTrue() throws {
        let json = #"{"apps": ["com.test.app"]}"#.data(using: .utf8)!
        let requirements = try JSONDecoder().decode(ActionRequirements.self, from: json)
        XCTAssertTrue(requirements.requiresSelection)

        let context = ActionContext(selectedText: "   ")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testDecodedRequirementsExplicitFalseAllowsEmptySelection() throws {
        let json = #"{"requires-selection": false}"#.data(using: .utf8)!
        let requirements = try JSONDecoder().decode(ActionRequirements.self, from: json)
        XCTAssertFalse(requirements.requiresSelection)

        let context = ActionContext(selectedText: "")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    func testRequiresSelectionTreatsOCRAsNonblankInputAndKeepsSourceAppGates() {
        let ocrContext = ActionContext(selectedText: "recognized text", bundleID: "com.test.app", source: .ocr)
        let inputRequired = ActionVisibility.isEnabled(
            requirements: ActionRequirements(regex: "^recognized", apps: ["com.test.app"], requiresSelection: true),
            legacyRegex: nil,
            context: ocrContext
        )
        let wrongSourceApp = ActionVisibility.isEnabled(
            requirements: ActionRequirements(apps: ["com.other.app"], requiresSelection: true),
            legacyRegex: nil,
            context: ocrContext
        )
        let whitespaceOCR = ActionContext(selectedText: " \n ", source: .ocr)
        let emptyInputRequired = ActionVisibility.isEnabled(
            requirements: ActionRequirements(requiresSelection: true),
            legacyRegex: nil,
            context: whitespaceOCR
        )
        let emptyInputAllowed = ActionVisibility.isEnabled(
            requirements: ActionRequirements(requiresSelection: false),
            legacyRegex: nil,
            context: whitespaceOCR
        )

        XCTAssertTrue(inputRequired.enabled)
        XCTAssertFalse(wrongSourceApp.enabled)
        XCTAssertFalse(emptyInputRequired.enabled)
        XCTAssertTrue(emptyInputAllowed.enabled)
    }

    func testInputRequirementMatrixAcrossSourceAndEditability() {
        let cases: [(String, SelectionSource, Bool?, Bool)] = [
            ("", .selection, true, false),
            ("text", .selection, true, true),
            ("text", .selection, false, true),
            ("text", .selection, nil, true),
            ("text", .clipboard, false, true),
            ("text", .ocr, false, true)
        ]
        func context(_ item: (String, SelectionSource, Bool?, Bool)) -> ActionContext {
            ActionContext(selection: SelectionContext(
                text: item.0,
                source: item.1,
                isEditable: item.2,
                pasteTargetAvailable: true
            ))
        }

        for item in cases {
            XCTAssertTrue(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .optional), legacyRegex: nil, context: context(item)
            ).enabled, "optional should allow \(item)")
            XCTAssertEqual(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .text), legacyRegex: nil, context: context(item)
            ).enabled, item.3, "text requirement for \(item)")
            XCTAssertEqual(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .liveSelection), legacyRegex: nil, context: context(item)
            ).enabled, item.1 == .selection && item.3, "liveSelection requirement for \(item)")
            XCTAssertEqual(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .editableSelection), legacyRegex: nil, context: context(item)
            ).enabled, item.1 == .selection && item.2 == true && item.3, "editableSelection requirement for \(item)")
        }
    }

    func testRequiresPasteTargetFailsClosedOnlyWhenRequested() {
        for availability in [true, false, nil] as [Bool?] {
            let context = ActionContext(selection: SelectionContext(
                text: "input", source: .clipboard, isEditable: false, pasteTargetAvailable: availability
            ))
            XCTAssertTrue(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .optional), legacyRegex: nil, context: context
            ).enabled)
            XCTAssertEqual(ActionVisibility.isEnabled(
                requirements: ActionRequirements(input: .optional, requiresPasteTarget: true),
                legacyRegex: nil,
                context: context
            ).enabled, availability == true)
        }
    }

    func testSelectionContextClonePreservesSourceCapabilities() {
        let selection = SelectionContext(
            text: "editable",
            source: .selection,
            isEditable: true,
            pasteTargetAvailable: true
        )
        let moved = selection.with(cursorPosition: CGPoint(x: 10, y: 20))
        XCTAssertEqual(moved.source, .selection)
        XCTAssertEqual(moved.isEditable, true)
        XCTAssertEqual(moved.pasteTargetAvailable, true)
    }

    func testInputDecodingMapsLegacyAliasesAndRejectsConflictsOrUnknownValues() throws {
        let oldTrue = try JSONDecoder().decode(ActionRequirements.self, from: #"{"requiresSelection":true}"#.data(using: .utf8)!)
        let oldFalse = try JSONDecoder().decode(ActionRequirements.self, from: #"{"requires-selection":false}"#.data(using: .utf8)!)
        XCTAssertEqual(oldTrue.input, .text)
        XCTAssertEqual(oldFalse.input, .optional)
        XCTAssertEqual(try JSONDecoder().decode(ActionRequirements.self, from: #"{}"#.data(using: .utf8)!).input, .text)
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"input":"editableSelection","requiresSelection":true}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"input":"surprise"}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"input":true}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"input":null}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"input":null,"requiresSelection":true}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"requiresPasteTarget":null}"#.data(using: .utf8)!))
        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: #"{"requiresSelection":true,"requires-selection":false}"#.data(using: .utf8)!))
    }

    // MARK: - Regex match / negation

    func testRegexEnablesWhenMatches() {
        let requirements = ActionRequirements(regex: "^[a-z]+$")
        let context = ActionContext(selectedText: "hello")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    func testRegexDisablesWhenDoesNotMatch() {
        let requirements = ActionRequirements(regex: "^[a-z]+$")
        let context = ActionContext(selectedText: "Hello World 123")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testNegatedRegexEnablesWhenNoMatch() {
        let requirements = ActionRequirements(regex: "^[0-9]+$", regexNegated: true)
        let context = ActionContext(selectedText: "hello")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    func testNegatedRegexDisablesWhenMatch() {
        let requirements = ActionRequirements(regex: "^[0-9]+$", regexNegated: true)
        let context = ActionContext(selectedText: "12345")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertFalse(result.enabled)
    }

    func testLegacyRegexUsedWhenRequirementsHasNone() {
        let context = ActionContext(selectedText: "hello")
        let matching = ActionVisibility.isEnabled(requirements: nil, legacyRegex: "^[a-z]+$", context: context)
        XCTAssertTrue(matching.enabled)
        let nonMatching = ActionVisibility.isEnabled(requirements: nil, legacyRegex: "^[0-9]+$", context: context)
        XCTAssertFalse(nonMatching.enabled)
    }

    func testMalformedRegexEnablesDefensively() {
        let requirements = ActionRequirements(regex: "(")
        let context = ActionContext(selectedText: "hello")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
    }

    // MARK: - ActionMatchInfo

    func testNoRegexBuildsMatchInfoEqualToText() {
        let context = ActionContext(selectedText: "hello")
        let result = ActionVisibility.isEnabled(requirements: nil, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
        XCTAssertEqual(result.match.text, "hello")
        XCTAssertEqual(result.match.matchedText, "hello")
        XCTAssertEqual(result.match.captures, [])
        XCTAssertEqual(result.match.sourceBundleID, "com.test.app")
    }

    func testRegexBuildsMatchInfoWithCaptures() {
        let requirements = ActionRequirements(regex: "^([a-z]+)@([a-z]+\\.[a-z]+)$")
        let context = ActionContext(selectedText: "a@b.com")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: context)
        XCTAssertTrue(result.enabled)
        XCTAssertEqual(result.match.text, "a@b.com")
        XCTAssertEqual(result.match.matchedText, "a@b.com")
        XCTAssertEqual(result.match.captures, ["a", "b.com"])
    }

    // MARK: - missingRequiredOptions (pure helper, never called from isEnabled)

    func testMissingRequiredOptionsReturnsEmptyValueIDs() {
        let requirements = ActionRequirements(requiredOptions: ["prefix", "suffix"])
        let resolved = ["prefix": "p", "suffix": "   "]
        XCTAssertEqual(ActionVisibility.missingRequiredOptions(requirements: requirements, resolvedOptions: resolved), ["suffix"])
    }

    func testMissingRequiredOptionsEmptyWhenAllResolved() {
        let requirements = ActionRequirements(requiredOptions: ["prefix"])
        XCTAssertEqual(ActionVisibility.missingRequiredOptions(requirements: requirements, resolvedOptions: ["prefix": "v"]), [])
    }

    func testMissingRequiredOptionsEmptyWhenNoneRequired() {
        XCTAssertEqual(ActionVisibility.missingRequiredOptions(requirements: nil, resolvedOptions: [:]), [])
    }

    // MARK: - End-to-end: URL {matched} encoding

    func testURLMatchedPlaceholderIsEncoded() async throws {
        let rules = ExtensionActionRules(requirements: ActionRequirements(regex: "a@b\\.com"))
        let action = URLTemplateAction(
            id: "test.url",
            title: "URL",
            icon: .symbol("link"),
            urlTemplate: "https://example.com/u/{matched}",
            rules: rules
        )
        let context = ActionContext(selectedText: "contact a@b.com now")
        XCTAssertTrue(action.isEnabled(for: context))

        // Mirror the popup's match plumbing: re-run visibility, thread the match into perform.
        let matchContext = ActionContext(selection: context.selection, modifiers: context.modifiers, match: action.matchInfo(for: context))
        let result = try await action.perform(matchContext)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://example.com/u/a%40b.com")
        } else {
            XCTFail("Expected .openURL result, got \(result)")
        }
    }

    func testURLCapturePlaceholders() async throws {
        let rules = ExtensionActionRules(requirements: ActionRequirements(regex: "^([a-z]+)@([a-z]+\\.[a-z]+)$"))
        let action = URLTemplateAction(
            id: "test.captures",
            title: "Captures",
            icon: .symbol("link"),
            urlTemplate: "https://example.com/domain/{capture2}/user/{1}",
            rules: rules
        )
        let context = ActionContext(selectedText: "a@b.com")
        let matchContext = ActionContext(selection: context.selection, modifiers: context.modifiers, match: action.matchInfo(for: context))
        let result = try await action.perform(matchContext)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.absoluteString, "https://example.com/domain/b.com/user/a")
        } else {
            XCTFail("Expected .openURL result, got \(result)")
        }
    }

    // MARK: - End-to-end: shell env vars

    func testScriptActionExportsMatchedCaptureAndBundleEnv() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("env_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo "MATCHED=$OPENCLIP_MATCHED CAPTURE1=$OPENCLIP_CAPTURE_1 BUNDLE=$OPENCLIP_BUNDLE_ID"
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        defer { try? FileManager.default.removeItem(at: tempScript) }

        let rules = ExtensionActionRules(requirements: ActionRequirements(regex: "^([a-z]+)@([a-z]+\\.[a-z]+)$"))
        let action = ScriptAction(
            id: "test.env",
            title: "Env",
            icon: .symbol("terminal"),
            scriptURL: tempScript,
            rules: rules
        )
        let context = ActionContext(selectedText: "a@b.com", bundleID: "com.test.app")
        let matchContext = ActionContext(selection: context.selection, modifiers: context.modifiers, match: action.matchInfo(for: context))
        let result = try await action.perform(matchContext)
        if case .text(let text) = result {
            XCTAssertEqual(
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                "MATCHED=a@b.com CAPTURE1=a BUNDLE=com.test.app"
            )
        } else {
            XCTFail("Expected .text result, got \(result)")
        }
    }

    func testNativeContentMatchesEmbeddedURLsAndSharesExecutionData() {
        let context = ActionContext(selectedText: "Read https://example.com, then https://github.com.")
        let rules = ExtensionActionRules(requirements: ActionRequirements(content: [.url]))
        let result = rules.resolveVisibility(for: context)
        XCTAssertTrue(result.enabled)
        XCTAssertEqual(result.match.detected.urls, ["https://example.com", "https://github.com"])
        XCTAssertEqual(result.match.detected, context.selection.detectedContent(for: [.url]))
    }

    func testContentTypesAreAlternativesAndUnrequestedResultsStayEmpty() {
        let context = ActionContext(selectedText: "Email user@example.com about https://github.com.")
        let emailOnly = ActionVisibility.isEnabled(requirements: ActionRequirements(content: [.email]), legacyRegex: nil, context: context)
        XCTAssertTrue(emailOnly.enabled)
        XCTAssertEqual(emailOnly.match.detected.emails, ["user@example.com"])
        XCTAssertTrue(emailOnly.match.detected.urls.isEmpty)
        let alternatives = ExtensionActionRules(requirements: ActionRequirements(content: [.phone, .email]))
        XCTAssertTrue(alternatives.resolveVisibility(for: context).enabled)
        XCTAssertFalse(alternatives.resolveVisibility(for: ActionContext(selectedText: "ordinary text")).enabled)
        XCTAssertFalse(alternatives.resolveVisibility(for: ActionContext(selectedText: "")).enabled)
    }

    func testContentAndExistingRequirementsMustAllPass() {
        let requirements = ActionRequirements(regex: "^Read", apps: ["com.test.app"], content: [.url])
        let matches = ActionContext(selectedText: "Read https://example.com")
        XCTAssertTrue(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: matches).enabled)
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: ActionContext(selectedText: "Visit https://example.com")).enabled)
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: ActionContext(selectedText: "Read https://example.com", bundleID: "com.other.app")).enabled)
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, context: ActionContext(selectedText: "Read ordinary text")).enabled)
        let live = ActionRequirements(input: .liveSelection, content: [.url])
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: live, legacyRegex: nil, context: ActionContext(selectedText: "https://example.com", source: .clipboard)).enabled)
        let paste = ActionRequirements(requiresPasteTarget: true, content: [.url])
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: paste, legacyRegex: nil, context: matches).enabled)
    }

    func testMalformedRegexCannotBypassContentRequirement() {
        let rules = ExtensionActionRules(requirements: ActionRequirements(regex: "(", content: [.url]))
        XCTAssertFalse(rules.resolveVisibility(for: ActionContext(selectedText: "ordinary text")).enabled)
        XCTAssertTrue(rules.resolveVisibility(for: ActionContext(selectedText: "https://example.com")).enabled)
    }

    func testContentRulesRoundTripAndRejectInvalidOrRetiredRequirements() throws {
        let rules = ExtensionActionRules(requirements: ActionRequirements(content: [.url, .email]))
        let decoded = try JSONDecoder().decode(ExtensionActionRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
        for source in [#"{"content":[]}"#, #"{"content":["unknown"]}"#, #"{"content":"url"}"#, #"{"content":null}"#, #"{"expression":"isURL(text)"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ActionRequirements.self, from: Data(source.utf8)))
        }
    }
}
