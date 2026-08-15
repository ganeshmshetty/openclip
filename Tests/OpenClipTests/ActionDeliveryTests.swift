import XCTest
import Core

final class ActionDeliveryTests: XCTestCase {
    func testNoneIsEmpty() {
        XCTAssertEqual(ActionDelivery.none, ActionDelivery())
    }
    func testInitDefaults() {
        let d = ActionDelivery()
        XCTAssertNil(d.secondary)
        XCTAssertNil(d.primaryToast)
        XCTAssertNil(d.secondaryToast)
    }
    func testHoldsDeclaredValues() {
        let toast = StatusFeedback(message: "Copied", style: .success)
        let d = ActionDelivery(secondary: .copy("x"), primaryToast: toast, secondaryToast: nil)
        guard case .copy(let t)? = d.secondary else { return XCTFail("expected copy") }
        XCTAssertEqual(t, "x")
        XCTAssertEqual(d.primaryToast, toast)
    }
    /// Every conformer gets the nil default without declaring it.
    func testProtocolDefaultIsNil() {
        struct NoDelivery: Action {
            let id = "t"; let title = "t"; let icon = ActionIcon.symbol("t")
            var chrome: ActionChrome { ActionChrome(source: .builtin) }
            func isEnabled(for context: ActionContext) -> Bool { true }
            func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
            func perform(_ context: ActionContext) async throws -> ActionResult { .success }
        }
        XCTAssertNil(NoDelivery().delivery)
    }
}
