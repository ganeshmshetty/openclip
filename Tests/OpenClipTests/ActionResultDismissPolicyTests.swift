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

    func testTextDoesNotDismissPopup() {
        XCTAssertFalse(ActionResult.text("x").dismissesPopup)
        XCTAssertFalse(ActionResult.sequence([.copy("x"), .text("y")]).dismissesPopup)
    }

    func testToastDismissesPopupByDefault() {
        XCTAssertTrue(ActionResult.toast(.init(message: "ok", style: .success)).dismissesPopup)
        XCTAssertTrue(ActionResult.toast(.init(message: "boom", style: .error)).dismissesPopup)
        XCTAssertFalse(ActionResult.toast(.init(message: "stick", style: .info, keepVisible: true)).dismissesPopup)
    }

    // MARK: - Decision 9: errors surface as .toast(.error), a dismissing toast

    func testErrorToastDismissesPopup() {
        let status = StatusFeedback(error: DummyError())
        XCTAssertEqual(status.style, .error)
        XCTAssertTrue(ActionResult.toast(status).dismissesPopup)
    }

    func testKeepVisibleToastInSequenceForcesPopupOpen() {
        let seq = ActionResult.sequence([.toast(.init(message: "working", style: .info, keepVisible: true)), .copy("x")])
        XCTAssertFalse(seq.dismissesPopup)
        let dismiss = ActionResult.sequence([.toast(.init(message: "done", style: .success)), .copy("x")])
        XCTAssertTrue(dismiss.dismissesPopup)
    }

    func testContainsToast() {
        XCTAssertTrue(ActionResult.toast(.init(message: "t", style: .info)).containsToast)
        XCTAssertTrue(ActionResult.sequence([.copy("x"), .toast(.init(message: "t", style: .info))]).containsToast)
        XCTAssertFalse(ActionResult.copy("x").containsToast)
        XCTAssertFalse(ActionResult.text("x").containsToast)
        XCTAssertFalse(ActionResult.sequence([.copy("x"), .paste("y")]).containsToast)
        XCTAssertFalse(ActionResult.sequence([.copy("x"), .text("y")]).containsToast)
    }
}
