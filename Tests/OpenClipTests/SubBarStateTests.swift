// SubBarStateTests.swift
import XCTest
import Core
@testable import OpenClip

private struct DummySubAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    var isEnabledValue: Bool = true
    @MainActor func isEnabled(for context: ActionContext) -> Bool { isEnabledValue }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

final class SubBarStateTests: XCTestCase {

    @MainActor
    func testDelayedLocalHoverExitDoesNotCancelTrackedGroupDwell() async throws {
        let hover = PopupHoverState()
        hover.usesGlobalMouseMonitoring = true
        let group = GroupAction(id: "group.hover", title: "Group", icon: .symbol("folder"),
                                chrome: ActionChrome(popupBehavior: .showSubActions))
        let subBar = SubBarPanelController()
        defer { subBar.hide() }
        var opened = false
        var localDwellRequests = 0
        let view = PopupView(
            actions: [group], context: ActionContext(selection: SelectionContext(text: "test")),
            hoverState: hover, onResult: { _ in },
            onRequestSubBarDwell: { _, _, _ in localDwellRequests += 1 },
            onCancelSubBarDwell: { subBar.cancelDwell() }
        )

        // The cursor-tracking path has already started the timer. SwiftUI relayout then
        // reports an exit and re-entry, despite the pointer remaining over this group.
        subBar.startDwell { opened = true }
        view.useLocalHoverFallback(for: .action(0), isHovering: false)
        view.useLocalHoverFallback(for: .action(0), isHovering: true)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(opened, "A delayed SwiftUI exit must not cancel the tracked hover timer")
        XCTAssertEqual(localDwellRequests, 0, "Local re-entry must not restart a tracked dwell")
    }

    @MainActor
    func testActiveSubGroupStateEquality() {
        let a = ActiveSubGroupState(
            groupID: "group.dev-tools",
            parentIndex: 2,
            subActionIDs: ["group.dev-tools.json", "group.dev-tools.base64"],
            isPinned: false,
            parentButtonFrame: CGRect(x: 80, y: 0, width: 40, height: 29)
        )
        let b = ActiveSubGroupState(
            groupID: "group.dev-tools",
            parentIndex: 2,
            subActionIDs: ["group.dev-tools.json", "group.dev-tools.base64"],
            isPinned: false,
            parentButtonFrame: CGRect(x: 80, y: 0, width: 40, height: 29)
        )
        XCTAssertEqual(a, b)
    }

    @MainActor
    func testActiveSubGroupStatePinnedDiffers() {
        let a = ActiveSubGroupState(
            groupID: "group.dev-tools",
            parentIndex: 2,
            subActionIDs: ["group.dev-tools.json"],
            isPinned: false,
            parentButtonFrame: .zero
        )
        let b = ActiveSubGroupState(
            groupID: "group.dev-tools",
            parentIndex: 2,
            subActionIDs: ["group.dev-tools.json"],
            isPinned: true,
            parentButtonFrame: .zero
        )
        XCTAssertNotEqual(a, b)
    }

    @MainActor
    func testSubActionHoverTarget() {
        let target = PopupHoverTarget.subAction(3)
        XCTAssertEqual(target, PopupHoverTarget.subAction(3))
        XCTAssertNotEqual(target, PopupHoverTarget.subAction(4))
        XCTAssertNotEqual(target, PopupHoverTarget.action(3))
    }

    @MainActor
    func testModeStoreSubBarFlag() {
        let store = PopupModeStore()
        XCTAssertFalse(store.isSubBarActive)
        store.isSubBarActive = true
        XCTAssertTrue(store.isSubBarActive)
    }

    @MainActor
    func testFastSwitchClosesSubBarWhenNextActionHasNoChildren() {
        let group1 = GroupAction(
            id: "group.one",
            title: "One",
            icon: .symbol("star"),
            chrome: ActionChrome(popupBehavior: .showSubActions)
        )
        let sub1 = DummySubAction(id: "group.one.a", title: "A")
        let plainAction = DummySubAction(id: "plain.action", title: "Plain")
        let catalog: [any Action] = [group1, sub1, plainAction]

        let resolver = SubActionResolver()
        let children1 = resolver.subActions(of: group1, in: catalog)
        XCTAssertFalse(children1.isEmpty)

        let childrenPlain = resolver.subActions(of: plainAction, in: catalog)
        XCTAssertTrue(childrenPlain.isEmpty)
    }
}
