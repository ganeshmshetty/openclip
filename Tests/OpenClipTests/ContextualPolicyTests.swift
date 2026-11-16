import XCTest
@testable import Core

private struct RulesAction: Action, ActionWithRules {
    let id: String
    let rules: ExtensionActionRules?
    let chrome: ActionChrome

    init(
        id: String = "com.test.rule",
        requirements: ActionRequirements? = nil,
        legacyRegex: String? = nil,
        contextual: Bool? = nil
    ) {
        self.id = id
        self.rules = ExtensionActionRules(requirements: requirements, legacyRegex: legacyRegex)
        self.chrome = ActionChrome(contextualOverride: contextual)
    }

    var title: String { id }
    var icon: ActionIcon { .symbol("circle") }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

final class ContextualPolicyTests: XCTestCase {
    func testExplicitTrueWinsWithoutRequirements() {
        let action = RulesAction(contextual: true)
        XCTAssertTrue(action.isContextual)
        XCTAssertEqual(ContextualPolicy.decision(for: action).reason, .explicitTrue)
    }

    func testExplicitFalseWinsOverNarrowingRequirements() {
        let action = RulesAction(
            requirements: ActionRequirements(apps: ["com.test.app"]),
            contextual: false
        )
        XCTAssertFalse(action.isContextual)
        XCTAssertEqual(ContextualPolicy.decision(for: action).reason, .explicitFalse)
    }

    func testAppsRequirementIsContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(apps: ["com.test.app"])).isContextual)
    }

    func testContentRequirementIsContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(content: [.url])).isContextual)
    }

    func testRegexRequirementIsContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(regex: "^https?://")).isContextual)
    }

    func testPredicateRequirementIsContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(predicate: "visible.js")).isContextual)
    }

    func testRequiresPasteTargetIsContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(requiresPasteTarget: true)).isContextual)
    }

    func testLiveAndEditableInputAreContextual() {
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(input: .liveSelection)).isContextual)
        XCTAssertTrue(RulesAction(requirements: ActionRequirements(input: .editableSelection)).isContextual)
    }

    func testInputTextAndOptionalAreNotContextual() {
        XCTAssertFalse(RulesAction(requirements: ActionRequirements(input: .text)).isContextual)
        XCTAssertFalse(RulesAction(requirements: ActionRequirements(input: .optional)).isContextual)
    }

    func testRequiredOptionsAloneIsNotContextual() {
        XCTAssertFalse(RulesAction(requirements: ActionRequirements(requiredOptions: ["mode"])).isContextual)
    }

    func testLegacyRegexIsContextual() {
        XCTAssertTrue(RulesAction(legacyRegex: "^https?://").isContextual)
    }

    func testMenuRelevanceIsContextual() {
        let action = MenuDecoratedAction(
            base: RulesAction(),
            menuRelevanceRegex: "\\S"
        )
        XCTAssertTrue(action.isContextual)
    }

    func testBuiltInIdentityIsContextual() {
        XCTAssertTrue(CalculateAction().isContextual)
    }
}
