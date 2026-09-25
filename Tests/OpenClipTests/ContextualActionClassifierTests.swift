import XCTest
@testable import Core

final class ContextualActionClassifierTests: XCTestCase {

    private func urlTemplate(regex: String?) -> URLTemplateAction {
        URLTemplateAction(
            id: "ext.search",
            title: "Search",
            icon: .symbol("magnifyingglass"),
            urlTemplate: "https://example.com/?q={query}",
            regexPattern: regex
        )
    }

    private func customOpenURL(regex: String?) -> CustomAction {
        CustomAction(
            id: "custom.open",
            title: "Open",
            iconName: "link",
            type: .openURL(urlTemplate: "https://example.com"),
            rules: regex.map { ExtensionActionRules(legacyRegex: $0) }
        )
    }

    func testURLTemplateWithoutPatternIsNotContextual() {
        let action = urlTemplate(regex: nil)
        XCTAssertFalse(action.isContextual)
        XCTAssertNil(action.contextualTriggerDescription)
    }

    func testURLTemplateWithPatternIsContextual() {
        let action = urlTemplate(regex: "^https?://")
        XCTAssertTrue(action.isContextual)
        XCTAssertEqual(action.contextualTriggerDescription, "Matches pattern: ^https?://")
    }

    func testCustomOpenURLWithoutPatternIsNotContextual() {
        let action = customOpenURL(regex: nil)
        XCTAssertFalse(action.isContextual)
        XCTAssertNil(action.contextualTriggerDescription)
    }

    func testCustomOpenURLWithPatternIsContextual() {
        let action = customOpenURL(regex: "^https?://")
        XCTAssertTrue(action.isContextual)
        XCTAssertEqual(action.contextualTriggerDescription, "Matches pattern: ^https?://")
    }

    /// URL-template extensions default to a `.url` badge, so the badge alone must not make an
    /// action contextual — otherwise every generic web-search action jumps ahead of the user's
    /// saved action order.
    func testURLBadgeAloneIsNotContextual() {
        let action = urlTemplate(regex: nil)
        XCTAssertEqual(action.chrome.badge, .url)
        XCTAssertFalse(action.isContextual)
    }
}
