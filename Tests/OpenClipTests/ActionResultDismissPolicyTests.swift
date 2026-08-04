import XCTest
@testable import Core

final class ActionResultDismissPolicyTests: XCTestCase {
    private struct DummyError: Error {}

    private func makeBubble() -> BubbleContent {
        BubbleContent(title: "Test", rows: [.text("hi")], emphasis: .info)
    }

    // MARK: - Dismiss-policy matrix (decision 8)

    func testOpenConfigurationDismisses() {
        let request = ConfigurationRequest(actionID: "builtin.search")
        XCTAssertTrue(ActionResult.openConfiguration(request).dismissesPopup)
    }

    func testKeepVisibleSuppressesDismissal() {
        XCTAssertFalse(ActionResult.keepVisible(.copy("x")).dismissesPopup)
    }

    func testSequenceDismissesOnlyWhenAllItemsDismiss() {
        XCTAssertFalse(ActionResult.sequence([.copy("x"), .showBubble(makeBubble())]).dismissesPopup)
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
        XCTAssertFalse(ActionResult.showBubble(makeBubble()).dismissesPopup)
        XCTAssertFalse(ActionResult.showStatus(.init(message: "ok", style: .success)).dismissesPopup)
        XCTAssertFalse(ActionResult.showStatus(.init(message: "boom", style: .error)).dismissesPopup)
    }

    // MARK: - Decision 9: errors surface as .showStatus(.error) and the popup stays

    func testErrorStatusKeepsPopup() {
        let status = StatusFeedback(error: DummyError())
        XCTAssertEqual(status.style, .error)
        XCTAssertFalse(ActionResult.showStatus(status).dismissesPopup)
    }

    // MARK: - effectForHandler

    func testEffectForHandlerUnwrapsKeepVisible() {
        if case .copy(let text) = ActionResult.keepVisible(.copy("x")).effectForHandler {
            XCTAssertEqual(text, "x")
        } else {
            XCTFail("Expected effectForHandler to unwrap .keepVisible into .copy")
        }
    }

    func testEffectForHandlerPassesThroughLeaf() {
        if case .paste(let text) = ActionResult.paste("y").effectForHandler {
            XCTAssertEqual(text, "y")
        } else {
            XCTFail("Expected effectForHandler to pass .paste through unchanged")
        }
    }
}
