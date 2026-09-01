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

private struct DummyPasteAction: Action, PasteRequiringAction, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("doc.on.clipboard") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

final class SubBarStateTests: XCTestCase {
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
    func testSubBarExcludesPasteRequiringActionsWhenPasteUnavailable() {
        let group = GroupAction(
            id: "group.edit",
            title: "Edit",
            icon: .symbol("pencil"),
            chrome: ActionChrome(popupBehavior: .showSubActions)
        )
        let copySub = DummySubAction(id: "group.edit.copy", title: "Copy")
        let pasteSub = DummyPasteAction(id: "group.edit.paste", title: "Paste")
        let allGroupActions: [any Action] = [group, copySub, pasteSub]

        let availableActions: [any Action] = allGroupActions
        let pasteAvailable = false
        let subActions = pasteAvailable == false
            ? availableActions.filter { !($0 is any PasteRequiringAction) }
            : availableActions

        let resolver = SubActionResolver()
        let children = resolver.subActions(of: group, in: subActions)
        XCTAssertEqual(children.map(\.id), ["group.edit.copy"])
        XCTAssertFalse(children.contains(where: { $0 is any PasteRequiringAction }))
    }

    @MainActor
    func testSubBarIncludesPasteRequiringActionsWhenPasteAvailable() {
        let group = GroupAction(
            id: "group.edit",
            title: "Edit",
            icon: .symbol("pencil"),
            chrome: ActionChrome(popupBehavior: .showSubActions)
        )
        let copySub = DummySubAction(id: "group.edit.copy", title: "Copy")
        let pasteSub = DummyPasteAction(id: "group.edit.paste", title: "Paste")
        let allGroupActions: [any Action] = [group, copySub, pasteSub]

        let availableActions: [any Action] = allGroupActions
        let pasteAvailable: Bool? = true
        let subActions = pasteAvailable == false
            ? availableActions.filter { !($0 is any PasteRequiringAction) }
            : availableActions

        let resolver = SubActionResolver()
        let children = resolver.subActions(of: group, in: subActions)
        XCTAssertEqual(children.map(\.id), ["group.edit.copy", "group.edit.paste"])
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
