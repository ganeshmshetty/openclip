// ActionChromeDecisionTests.swift
// OpenClipTests

import XCTest
@testable import Core
@testable import OpenClip

final class ActionChromeDecisionTests: XCTestCase {
    func testDecisionSourceRoundTrip() throws {
        let chrome = ActionChrome(source: .decision, launchesDecisions: true)
        let data = try JSONEncoder().encode(chrome)
        let decoded = try JSONDecoder().decode(ActionChrome.self, from: data)
        XCTAssertEqual(decoded.source, .decision)
        XCTAssertTrue(decoded.launchesDecisions)
    }

    func testLegacyJSONDefaultsLaunchesDecisionsFalse() throws {
        let legacyJSON = """
        {
            "badge": "none",
            "rowStyle": "standard",
            "popupBehavior": "perform",
            "source": "builtin",
            "requiresLiveSelection": false,
            "launchesAI": false,
            "showsLoading": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActionChrome.self, from: legacyJSON)
        XCTAssertFalse(decoded.launchesDecisions)
    }

    func testDecisionDoesNotDismiss() {
        let presentation = DecisionPresentation(
            toolID: "t",
            toolTitle: "T",
            answers: [DecisionAnswer(id: "a", value: .noul(true))]
        )
        XCTAssertFalse(ActionResult.decision(presentation).dismissesPopup)
        XCTAssertFalse(ActionResult.decision(presentation).containsToast)
    }
}
