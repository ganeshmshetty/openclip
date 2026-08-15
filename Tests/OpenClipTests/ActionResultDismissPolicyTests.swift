import XCTest
@testable import Core

final class ActionResultDismissPolicyTests: XCTestCase {
    private struct DummyError: Error {}

    // MARK: - Dismiss-policy matrix (decision 8)

    func testOpenConfigurationDismisses() {
        let request = ConfigurationRequest(actionID: "builtin.search")
        XCTAssertTrue(ActionResult.openConfiguration(request).dismissesPopup)
    }

    func testSequenceDismissesOnlyWhenAllItemsDismiss() {
        XCTAssertTrue(ActionResult.sequence([.copy("x"), .paste("y")]).dismissesPopup)
        // An empty sequence never dismisses.
        XCTAssertFalse(ActionResult.sequence([]).dismissesPopup)
    }

    func testLeafEffectsDismiss() {
        XCTAssertTrue(ActionResult.copy("x").dismissesPopup)
        XCTAssertTrue(ActionResult.cut("x").dismissesPopup)
        XCTAssertTrue(ActionResult.paste("x").dismissesPopup)
        XCTAssertTrue(ActionResult.openURL(URL(string: "https://example.com")!).dismissesPopup)
        XCTAssertTrue(ActionResult.success.dismissesPopup)
        XCTAssertTrue(ActionResult.none.dismissesPopup)
        XCTAssertTrue(ActionResult.failure(DummyError()).dismissesPopup)
    }

    func testPresentationResultsKeepPopup() {
        XCTAssertFalse(ActionResult.showStatus(.init(message: "ok", style: .success)).dismissesPopup)
        XCTAssertFalse(ActionResult.showStatus(.init(message: "boom", style: .error)).dismissesPopup)
    }

    // MARK: - Decision 9: errors surface as .showStatus(.error) and the popup stays

    func testErrorStatusKeepsPopup() {
        let status = StatusFeedback(error: DummyError())
        XCTAssertEqual(status.style, .error)
        XCTAssertFalse(ActionResult.showStatus(status).dismissesPopup)
    }
}
