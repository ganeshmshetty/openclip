// TopLevelActionResolverTests.swift
// OpenClipTests
//
// Unit tests for pure TopLevelActionResolver.
import XCTest
@testable import Core

final class TopLevelActionResolverTests: XCTestCase {
    private struct DummyAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        let chrome: ActionChrome

        init(
            id: String,
            title: String = "Test Action",
            icon: ActionIcon = .symbol("sparkles"),
            chrome: ActionChrome
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.chrome = chrome
        }

        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    func testEmptyActionsReturnsEmptyList() {
        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: [],
            customGroupMemberIDs: [],
            disabledActionIDs: [],
            isAIEnabled: true
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testResolvesStandaloneBuiltinsAndExtensionsWithEnabledState() {
        let copyAction = DummyAction(
            id: "builtin.copy",
            title: "Copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let extAction = DummyAction(
            id: "com.user.wordcount",
            title: "Word Count",
            chrome: ActionChrome(badge: .custom, rowStyle: .standard, popupBehavior: .perform, source: .custom)
        )

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: [copyAction, extAction],
            customGroupMemberIDs: [],
            disabledActionIDs: ["builtin.copy"],
            isAIEnabled: true
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "builtin.copy")
        XCTAssertEqual(items[0].title, "Copy")
        XCTAssertEqual(items[0].icon, .symbol("sparkles"))
        XCTAssertFalse(items[0].isGroup)
        XCTAssertFalse(items[0].isEnabled)

        XCTAssertEqual(items[1].id, "com.user.wordcount")
        XCTAssertEqual(items[1].title, "Word Count")
        XCTAssertEqual(items[1].icon, .symbol("sparkles"))
        XCTAssertFalse(items[1].isGroup)
        XCTAssertTrue(items[1].isEnabled)
    }

    func testResolvesCustomGroupsAsSingleItemsAndOmitsMembers() {
        let groupAction = CustomGroupAction(
            id: "vgroup.clipboard",
            title: "Clipboard",
            iconName: "folder",
            memberActionIDs: ["builtin.copy", "builtin.paste"]
        )
        let copyAction = DummyAction(
            id: "builtin.copy",
            title: "Copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let pasteAction = DummyAction(
            id: "builtin.paste",
            title: "Paste",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let standaloneAction = DummyAction(
            id: "builtin.upper",
            title: "Uppercase",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )

        let actions: [any Action] = [groupAction, copyAction, pasteAction, standaloneAction]
        let customGroupMemberIDs: Set<String> = ["builtin.copy", "builtin.paste"]

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: customGroupMemberIDs,
            disabledActionIDs: [],
            isAIEnabled: true
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "vgroup.clipboard")
        XCTAssertEqual(items[0].title, "Clipboard")
        XCTAssertTrue(items[0].isGroup)
        XCTAssertTrue(items[0].isEnabled)

        XCTAssertEqual(items[1].id, "builtin.upper")
        XCTAssertEqual(items[1].title, "Uppercase")
        XCTAssertFalse(items[1].isGroup)
        XCTAssertTrue(items[1].isEnabled)
    }

    func testResolvesExtensionGroupsAndOmitsPackageSubActions() {
        let groupAction = DummyAction(
            id: "com.pkg.tools",
            title: "Dev Tools",
            chrome: ActionChrome(badge: .extensionPkg("Dev Tools"), rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.tools"))
        )
        let subAction1 = DummyAction(
            id: "com.pkg.tools.format",
            title: "Format JSON",
            chrome: ActionChrome(badge: .extensionPkg("Dev Tools"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.tools"))
        )
        let subAction2 = DummyAction(
            id: "com.pkg.tools.validate",
            title: "Validate JSON",
            chrome: ActionChrome(badge: .extensionPkg("Dev Tools"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.tools"))
        )

        let actions: [any Action] = [groupAction, subAction1, subAction2]

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: [],
            disabledActionIDs: ["com.pkg.tools"],
            isAIEnabled: true
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "com.pkg.tools")
        XCTAssertEqual(items[0].title, "Dev Tools")
        XCTAssertTrue(items[0].isGroup)
        XCTAssertFalse(items[0].isEnabled)
    }

    func testOmitsAIPresetsAndResolvesAIToolsLauncher() {
        let aiPreset = DummyAction(
            id: "ai.preset.summarize",
            title: "Summarize",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
        )
        let aiLauncher = DummyAction(
            id: "builtin.ai",
            title: "AI Tools",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
        )
        let copyAction = DummyAction(
            id: "builtin.copy",
            title: "Copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )

        let actions: [any Action] = [aiPreset, aiLauncher, copyAction]

        let itemsEnabled = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: [],
            disabledActionIDs: [],
            isAIEnabled: true
        )

        XCTAssertEqual(itemsEnabled.count, 2)
        XCTAssertEqual(itemsEnabled[0].id, "builtin.ai")
        XCTAssertTrue(itemsEnabled[0].isAI)
        XCTAssertTrue(itemsEnabled[0].isEnabled)
        XCTAssertEqual(itemsEnabled[1].id, "builtin.copy")

        let itemsDisabled = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: [],
            disabledActionIDs: [],
            isAIEnabled: false
        )

        XCTAssertEqual(itemsDisabled[0].id, "builtin.ai")
        XCTAssertFalse(itemsDisabled[0].isEnabled)
    }
}
