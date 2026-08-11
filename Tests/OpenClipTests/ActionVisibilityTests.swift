import XCTest
@testable import Core

private extension ActionContext {
    init(selectedText: String, bundleID: String? = "com.test.app") {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: bundleID, localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        self.init(selection: selection, modifiers: [])
    }
}

@MainActor
final class ActionVisibilityTests: XCTestCase {
    private func attemptParse(_ source: String) -> ValidateExpression {
        // Test-only: source strings here are known-valid; parse failure would surface as a force-trap.
        try! ValidateExpression.parse(source).get()
    }

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

    func testDecodedRequirementsExpressionSurvivesRoundTrip() throws {
        let json = #"{"expression": "isEmail(text)"}"#.data(using: .utf8)!
        let requirements = try JSONDecoder().decode(ActionRequirements.self, from: json)
        XCTAssertEqual(requirements.expression, "isEmail(text)")

        let data = try JSONEncoder().encode(requirements)
        let roundTripped = try JSONDecoder().decode(ActionRequirements.self, from: data)
        XCTAssertEqual(roundTripped.expression, "isEmail(text)")
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

    // MARK: - Regex match / negation

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
        if case .paste(let text) = result {
            XCTAssertEqual(
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                "MATCHED=a@b.com CAPTURE1=a BUNDLE=com.test.app"
            )
        } else {
            XCTFail("Expected .paste result, got \(result)")
        }
    }

    // MARK: - expression gate

    func testExpressionGateDisablesWhenEvaluatesFalse() {
        let requirements = ActionRequirements(expression: "isEmail(text)")
        let context = ActionContext(selectedText: "not an email")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: attemptParse("isEmail(text)"), context: context)
        XCTAssertFalse(result.enabled)
    }

    func testExpressionGateEnablesWhenEvaluatesTrue() {
        let requirements = ActionRequirements(expression: "isEmail(text)")
        let context = ActionContext(selectedText: "a@b.com")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: attemptParse("isEmail(text)"), context: context)
        XCTAssertTrue(result.enabled)
    }

    func testRegexAndExpressionBothMustPass() {
        let requirements = ActionRequirements(regex: "^[a-z]+@", expression: "length(text) >= 8")
        let expression = attemptParse("length(text) >= 8")

        let bothPass = ActionContext(selectedText: "user@example.com")
        XCTAssertTrue(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: expression, context: bothPass).enabled)

        let regexPassesExpressionFails = ActionContext(selectedText: "a@b.co")
        // regex ^[a-z]+@ matches, but length < 8
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: expression, context: regexPassesExpressionFails).enabled)

        let regexFails = ActionContext(selectedText: "123@example.com")
        // regex first pass fails -> disabled without evaluating the expression
        XCTAssertFalse(ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: expression, context: regexFails).enabled)
    }

    func testLegacyRegexWithExpressionGate() {
        let context = ActionContext(selectedText: "hello world")
        let expression = attemptParse("contains(text, \"world\")")
        let passing = ActionVisibility.isEnabled(requirements: nil, legacyRegex: "^hello", expression: expression, context: context)
        XCTAssertTrue(passing.enabled)
        let failingExpr = attemptParse("contains(text, \"moon\")")
        let failing = ActionVisibility.isEnabled(requirements: nil, legacyRegex: "^hello", expression: failingExpr, context: context)
        XCTAssertFalse(failing.enabled)
    }

    func testExpressionRuntimeErrorDisables() {
        let requirements = ActionRequirements(expression: "length(text) == \"x\"")
        let context = ActionContext(selectedText: "hello")
        let result = ActionVisibility.isEnabled(requirements: requirements, legacyRegex: nil, expression: attemptParse("length(text) == \"x\""), context: context)
        XCTAssertFalse(result.enabled) // fail-closed on eval error
    }

    func testExpressionWithoutRequirementsGatesAlone() {
        let context = ActionContext(selectedText: "a@b.com")
        let passing = ActionVisibility.isEnabled(requirements: nil, legacyRegex: nil, expression: attemptParse("isEmail(text)"), context: context)
        XCTAssertTrue(passing.enabled)
    }

    func testResolveVisibilityCarriesCompiledExpression() {
        let expression = try! ValidateExpression.parse("length(text) > 5").get()
        let rules = ExtensionActionRules(
            requirements: ActionRequirements(expression: "length(text) > 5"),
            compiledExpression: expression
        )
        let short = ActionContext(selectedText: "hi")
        let long = ActionContext(selectedText: "a longer selection")
        XCTAssertFalse(rules.resolveVisibility(for: short).enabled)
        XCTAssertTrue(rules.resolveVisibility(for: long).enabled)
    }

    func testResolveVisibilityWithoutExpressionDelegateToRegex() {
        let rules = ExtensionActionRules(requirements: ActionRequirements(regex: "^[0-9]+$"))
        XCTAssertTrue(rules.resolveVisibility(for: ActionContext(selectedText: "12345")).enabled)
        XCTAssertFalse(rules.resolveVisibility(for: ActionContext(selectedText: "abc")).enabled)
    }

    func testRulesRoundTripDropsCompiledExpressionButKeepsSource() throws {
        let rules = ExtensionActionRules(
            requirements: ActionRequirements(expression: "isEmail(text)"),
            compiledExpression: try! ValidateExpression.parse("isEmail(text)").get()
        )
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(ExtensionActionRules.self, from: data)
        XCTAssertEqual(decoded.requirements?.expression, "isEmail(text)")
        XCTAssertNil(decoded.compiledExpression)
    }
}
