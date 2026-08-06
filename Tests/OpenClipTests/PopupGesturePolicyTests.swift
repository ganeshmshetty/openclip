import XCTest
@testable import Core

final class PopupGesturePolicyTests: XCTestCase {

    @MainActor
    func testCalculateGetsLongPressWithoutHover() {
        let action = CalculateAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .perform)
        XCTAssertEqual(policy.longPress, .showResultContent)
        XCTAssertFalse(policy.hoverPreview, "Calculate is long-press only; no hover preview")
    }

    @MainActor
    func testGroupActionShowsMenuWithoutLongPress() {
        let action = GroupAction(
            id: "ext.group",
            title: "Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions)
        )
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .openSubActions)
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
