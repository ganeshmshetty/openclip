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

    @MainActor
    func testRightNeighborUsesVisibleBarIndexNotUnfilteredCatalogIndex() {
        TestIsolation.reset()
        let left = DummySubAction(id: "plain.left", title: "Left")
        let group = GroupAction(
            id: "group.tools",
            title: "Tools",
            icon: .symbol("folder"),
            chrome: ActionChrome(popupBehavior: .showSubActions)
        )
        let child1 = DummySubAction(id: "group.tools.one", title: "One")
        let child2 = DummySubAction(id: "group.tools.two", title: "Two")
        let right = DummySubAction(id: "plain.right", title: "Right")
        let distantRight = DummySubAction(id: "plain.distant", title: "Distant")

        // Unfiltered catalog: children sit contiguously after the parent group (index 1),
        // shifting `right` to catalog index 4 while its visible bar slot is 2.
        let catalog: [any Action] = [left, group, child1, child2, right, distantRight]
        let context = ActionContext(selection: SelectionContext(text: "hello"))

        var reported: [(actionID: String?, targetID: String?, slotIndex: Int?)] = []
        let hover = PopupHoverState()
        hover.usesGlobalMouseMonitoring = false

        let view = PopupView(
            actions: catalog,
            context: context,
            hoverState: hover,
            onResult: { _ in },
            onHoveredActionChanged: { action, targetID, slotIndex in
                reported.append((action?.id, targetID, slotIndex))
            }
        )

        let subBar = SubBarPanelController()
        defer { subBar.hide() }
        subBar.show(
            for: group,
            parentIndex: 1,
            subActions: [child1, child2],
            parentButtonScreenFrame: CGRect(x: 100, y: 100, width: 39, height: 34),
            isPinned: false,
            effectiveTheme: "classic",
            effectiveColorScheme: .light,
            scale: 1,
            context: context,
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _, _ in },
            onWillPerformAction: { _, _ in true },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        // Left neighbor (slot 0) and right neighbor (slot 2) must both be immediate neighbors.
        view.useLocalHoverFallback(for: .action(0), isHovering: true)
        XCTAssertEqual(reported.last?.actionID, left.id)
        XCTAssertEqual(reported.last?.targetID, left.id)
        XCTAssertEqual(reported.last?.slotIndex, 0)
        XCTAssertTrue(subBar.isImmediateNeighbor(actionIndex: reported.last?.slotIndex ?? -1))

        view.useLocalHoverFallback(for: .action(2), isHovering: true)
        XCTAssertEqual(reported.last?.actionID, right.id)
        XCTAssertEqual(reported.last?.targetID, right.id)
        XCTAssertEqual(reported.last?.slotIndex, 2)
        XCTAssertTrue(subBar.isImmediateNeighbor(actionIndex: reported.last?.slotIndex ?? -1))

        // Distant right action (slot 3) must remain non-adjacent.
        view.useLocalHoverFallback(for: .action(3), isHovering: true)
        XCTAssertEqual(reported.last?.actionID, distantRight.id)
        XCTAssertEqual(reported.last?.slotIndex, 3)
        XCTAssertFalse(subBar.isImmediateNeighbor(actionIndex: reported.last?.slotIndex ?? -1))

        // Command palette button (.search) sits at slot 4 (distant from slot 1) with action == nil.
        view.useLocalHoverFallback(for: .search, isHovering: true)
        XCTAssertNil(reported.last?.actionID)
        XCTAssertEqual(reported.last?.targetID, "bar.search")
        XCTAssertEqual(reported.last?.slotIndex, 4)
        XCTAssertFalse(subBar.isImmediateNeighbor(actionIndex: reported.last?.slotIndex ?? -1))

        // When the open group sits immediately to the left of .search (slot 3), .search (slot 4) is an immediate neighbor.
        subBar.show(
            for: group,
            parentIndex: 3,
            subActions: [child1, child2],
            parentButtonScreenFrame: CGRect(x: 220, y: 100, width: 39, height: 34),
            isPinned: false,
            effectiveTheme: "classic",
            effectiveColorScheme: .light,
            scale: 1,
            context: context,
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _, _ in },
            onWillPerformAction: { _, _ in true },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )
        XCTAssertTrue(subBar.isImmediateNeighbor(actionIndex: reported.last?.slotIndex ?? -1))
    }
}
