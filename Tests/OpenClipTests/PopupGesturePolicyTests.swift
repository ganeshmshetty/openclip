import XCTest
@testable import Core

final class PopupGesturePolicyTests: XCTestCase {

    @MainActor
    func testCalculateGetsLongPressWithoutHover() {
        let action = CalculateAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .perform)
        XCTAssertEqual(policy.longPress, .showResultBubble)
        XCTAssertFalse(policy.hoverPreview, "Calculate is long-press only; no hover preview")
    }

    @MainActor
    func testTransformGroupShowsMenuWithoutLongPress() {
        let action = TransformTextGroupAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .showMenu)
        XCTAssertNil(policy.longPress)
        XCTAssertFalse(policy.hoverPreview)
    }

    @MainActor
    func testPlainPerformActionHasNoLongPress() {
        let action = CopyAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .perform)
        XCTAssertNil(policy.longPress)
        XCTAssertFalse(policy.hoverPreview)
    }
}
