import XCTest
@testable import Core

final class PopupGesturePolicyTests: XCTestCase {

    @MainActor
    func testCalculateIsPerformSingleClick() {
        let action = CalculateAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .perform)
    }

    @MainActor
    func testGroupActionShowsMenuOnSingleClick() {
        let action = GroupAction(
            id: "ext.group",
            title: "Group",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions)
        )
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .openSubActions)
    }

    @MainActor
    func testPlainPerformActionIsPerformSingleClick() {
        let action = CopyAction()
        let policy = action.gesturePolicy
        XCTAssertEqual(policy.singleClick, .perform)
    }
}
