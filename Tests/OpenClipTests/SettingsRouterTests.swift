// SettingsRouterTests.swift
// OpenClipTests
//
// Pins the settings window's navigation model: the router's path and history (what the toolbar's
// back/forward arrows walk), the sidebar's search matching, how installed extensions are derived
// from the action catalog for the sidebar's second group, and which page a row in the Actions
// list opens.

import XCTest
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class SettingsRouterTests: XCTestCase {

    // MARK: - Path and history

    func testStartsOnGeneralWithNowhereToGo() {
        let router = SettingsRouter()
        XCTAssertEqual(router.path, [.general])
        XCTAssertEqual(router.sidebarPage, .general)
        XCTAssertEqual(router.currentPage, .general)
        XCTAssertFalse(router.canGoBack)
        XCTAssertFalse(router.canGoForward)
    }

    func testSelectReplacesThePathAndRecordsEveryStep() {
        let router = SettingsRouter()
        router.select(.actions)
        router.push(.action(id: "builtin.search"))
        router.select(.ai)

        XCTAssertEqual(router.path, [.ai])
        XCTAssertEqual(router.history, [[.general], [.actions], [.actions, .action(id: "builtin.search")], [.ai]])
        XCTAssertTrue(router.canGoBack)
        XCTAssertFalse(router.canGoForward)
    }

    func testPushDrillsInAndPopComesBackOut() {
        let router = SettingsRouter()
        router.select(.actions)
        router.push(.action(id: "a"))
        XCTAssertEqual(router.path, [.actions, .action(id: "a")])
        XCTAssertEqual(router.sidebarPage, .actions, "the sidebar keeps the page the editor was reached from")
        XCTAssertEqual(router.currentPage, .action(id: "a"))

        router.pop()
        XCTAssertEqual(router.path, [.actions])
        XCTAssertEqual(router.history.last, [.actions], "pop is a navigation of its own, so it is recorded")
    }

    func testPopOnASidebarPageIsANoOp() {
        let router = SettingsRouter()
        router.select(.store)
        let before = router.history
        router.pop()
        XCTAssertEqual(router.path, [.store])
        XCTAssertEqual(router.history, before)
    }

    func testPushingAPageAlreadyInThePathReturnsToItInsteadOfStacking() {
        let router = SettingsRouter()
        router.select(.actions)
        router.push(.action(id: "a"))
        router.pushIconPicker(writingTo: .constant("bolt"))
        XCTAssertEqual(router.path.count, 3)

        router.push(.action(id: "a"))
        XCTAssertEqual(router.path, [.actions, .action(id: "a")])
    }

    func testBackAndForwardWalkTheHistory() {
        let router = SettingsRouter()
        router.select(.actions)
        router.push(.action(id: "a"))
        router.select(.about)

        router.goBack()
        XCTAssertEqual(router.path, [.actions, .action(id: "a")])
        XCTAssertTrue(router.canGoForward)

        router.goBack()
        XCTAssertEqual(router.path, [.actions])
        router.goBack()
        XCTAssertEqual(router.path, [.general])
        XCTAssertFalse(router.canGoBack)
        router.goBack()
        XCTAssertEqual(router.path, [.general], "back at the start is a no-op")

        router.goForward()
        router.goForward()
        router.goForward()
        XCTAssertEqual(router.path, [.about])
        XCTAssertFalse(router.canGoForward)
        router.goForward()
        XCTAssertEqual(router.path, [.about], "forward at the end is a no-op")
    }

    func testANewNavigationAfterGoingBackDropsTheForwardEntries() {
        let router = SettingsRouter()
        router.select(.actions)
        router.select(.about)
        router.goBack()
        XCTAssertTrue(router.canGoForward)

        router.select(.shortcuts)
        XCTAssertFalse(router.canGoForward)
        XCTAssertEqual(router.history, [[.general], [.actions], [.shortcuts]])
    }

    func testShowingTheCurrentPathAgainRecordsNothing() {
        let router = SettingsRouter()
        router.select(.actions)
        router.select(.actions)
        router.show(path: [.actions])
        XCTAssertEqual(router.history, [[.general], [.actions]])
    }

    func testSelectingTheSidebarPageWhileDrilledInReturnsToItsTop() {
        let router = SettingsRouter()
        router.select(.actions)
        router.push(.action(id: "a"))
        router.select(.actions)
        XCTAssertEqual(router.path, [.actions])
    }

    func testHistoryIsCapped() {
        let router = SettingsRouter()
        for step in 0..<(SettingsRouter.historyLimit + 40) {
            router.select(step % 2 == 0 ? .actions : .general)
        }
        XCTAssertEqual(router.history.count, SettingsRouter.historyLimit)
        XCTAssertEqual(router.historyIndex, SettingsRouter.historyLimit - 1)
        XCTAssertEqual(router.path, router.history.last)
    }

    func testOpenConfigurationOpensTheActionUnderActionsAndKeepsTheRequest() {
        let router = SettingsRouter()
        let action = StubAction(id: "com.example.tool.action.0", title: "Tool", chrome: Self.extensionChrome(package: "com.example.tool"))
        let request = ConfigurationRequest(actionID: action.id, reason: "Needs a key", missingOptionIDs: ["apiKey"])

        router.openConfiguration(for: action, request: request)

        XCTAssertEqual(router.path, [.actions, .action(id: action.id)])
        XCTAssertEqual(router.configurationRequest(for: action.id), request)
        router.clearConfigurationRequest(for: action.id)
        XCTAssertNil(router.configurationRequest(for: action.id))
    }

    func testIconPickerKeepsTheBindingItWasHanded() {
        let router = SettingsRouter()
        var symbol = "bolt"
        let binding = Binding(get: { symbol }, set: { symbol = $0 })
        router.select(.actions)
        router.push(.action(id: "a"))
        router.pushIconPicker(writingTo: binding)

        guard case .iconPicker = router.currentPage else {
            return XCTFail("expected the icon picker on top, got \(router.currentPage)")
        }
        router.iconTarget?.wrappedValue = "heart"
        XCTAssertEqual(symbol, "heart")
    }

    func testNoticesComeAndGo() {
        let router = SettingsRouter()
        XCTAssertNil(router.notice)
        router.notifyError(title: "Remove Failed", message: "Nope")
        XCTAssertEqual(router.notice?.title, "Remove Failed")
        XCTAssertEqual(router.notice?.style, .error)
        router.dismissNotice()
        XCTAssertNil(router.notice)
    }

    // MARK: - Sidebar search

    func testSidebarRowMatchesTitleOrKeywordsAndNeedsEveryWord() {
        let row = SettingsSidebarRow(page: .ai, title: "AI", keywords: ["model", "api key", "prompt"], tile: .symbol("sparkles", tint: .purple))
        XCTAssertTrue(row.matches("ai"))
        XCTAssertTrue(row.matches("API"), "case does not matter")
        XCTAssertTrue(row.matches("key"))
        XCTAssertTrue(row.matches("api prompt"), "every word can come from a different keyword")
        XCTAssertFalse(row.matches("api hotkey"), "one word that matches nothing rules the row out")
        XCTAssertFalse(row.matches("store"))
        XCTAssertTrue(row.matches("   "), "a blank query matches everything")
    }

    func testSidebarFilterKeepsEverythingForABlankQueryAndOrder() {
        let rows = SettingsPage.systemPages.map { SettingsSidebarRow(systemPage: $0) }
        XCTAssertEqual(SettingsSidebarFilter.filter(rows, query: "").map(\.page), SettingsPage.systemPages)
        XCTAssertEqual(SettingsSidebarFilter.filter(rows, query: "hotkey").map(\.page), [.general, .shortcuts])
        XCTAssertEqual(SettingsSidebarFilter.filter(rows, query: "licence").map(\.page), [.about])
    }

    // MARK: - Installed extensions

    func testInstalledExtensionsGroupByPackageSortByNameAndSkipWhatIsNotAnExtension() {
        let actions: [any Action] = [
            StubAction(id: "builtin.copy", title: "Copy", chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)),
            StubAction(id: "com.zeta.one.action.0", title: "Zeta", chrome: Self.extensionChrome(package: "com.zeta.one", badgeName: "Zeta")),
            StubAction(id: "com.alpha.two.action.0", title: "Alpha A", chrome: Self.extensionChrome(package: "com.alpha.two", badgeName: "Alpha")),
            StubAction(id: "com.alpha.two.action.1", title: "Alpha B", chrome: Self.extensionChrome(package: "com.alpha.two", badgeName: "Alpha")),
            StubAction(id: "custom.abc123", title: "My snippet", chrome: Self.extensionChrome(package: "custom.abc123", badgeName: "My snippet")),
            StubAction(id: "com.custom.legacy", title: "Legacy", chrome: Self.extensionChrome(package: "com.custom.legacy", badgeName: "Legacy")),
            StubAction(id: "ai.proofread", title: "Proofread", chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)),
        ]

        let infos = InstalledExtensionInfo.all(from: actions)
        XCTAssertEqual(infos.map(\.packageID), ["com.alpha.two", "com.zeta.one"])
        XCTAssertEqual(infos.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(infos[0].commands.map(\.id), ["com.alpha.two.action.0", "com.alpha.two.action.1"])
        XCTAssertNil(infos[0].containerActionID)
        XCTAssertNil(infos[0].gatedReason)
        XCTAssertTrue(InstalledExtensionInfo.isCustomPackage("custom.abc123"))
        XCTAssertTrue(InstalledExtensionInfo.isCustomPackage("com.custom.legacy"))
        XCTAssertFalse(InstalledExtensionInfo.isCustomPackage("com.openclip.jwt"))
    }

    func testAGroupPackageSeparatesItsContainerFromItsCommands() throws {
        let package = "com.openclip.jwt"
        let actions: [any Action] = [
            StubAction(id: "\(package).jwt", title: "JWT", chrome: Self.extensionChrome(package: package, badgeName: "JWT", popupBehavior: .showSubActions)),
            StubAction(id: "\(package).jwt.inspect", title: "Inspect", chrome: Self.extensionChrome(package: package, badgeName: "JWT")),
            StubAction(id: "\(package).jwt.verify", title: "Verify Signature", chrome: Self.extensionChrome(package: package, badgeName: "JWT")),
        ]

        let info = try XCTUnwrap(InstalledExtensionInfo.info(for: package, in: actions))
        XCTAssertEqual(info.name, "JWT")
        XCTAssertTrue(info.isGroup)
        XCTAssertEqual(info.containerActionID, "\(package).jwt")
        XCTAssertEqual(info.commands.map(\.id), ["\(package).jwt.inspect", "\(package).jwt.verify"])
        XCTAssertEqual(info.uninstallActionID, "\(package).jwt")
        XCTAssertNil(InstalledExtensionInfo.info(for: "com.nowhere", in: actions))
    }

    func testAGatedPackageReportsItsReasonAndHidesThePlaceholder() throws {
        let package = "com.example.gated"
        let gated = GatedExtensionAction(
            packageID: package,
            title: "Gated",
            icon: .symbol("lock"),
            chrome: Self.extensionChrome(package: package, badgeName: "Gated"),
            reason: .filesChanged
        )
        let info = try XCTUnwrap(InstalledExtensionInfo.info(for: package, in: [gated]))
        XCTAssertEqual(info.gatedReason, .filesChanged)
        XCTAssertTrue(info.commands.isEmpty, "the trust gate's placeholder is not something to configure")
        XCTAssertEqual(info.uninstallActionID, package)
        XCTAssertNotNil(extensionGateDescription(for: .filesChanged))
        XCTAssertNil(extensionGateDescription(for: .revoked), "a revoked package is explained by its switch being off")
    }

    // MARK: - Where a row goes

    func testActionRowsOpenTheRightPage() {
        let plain = StubAction(id: "builtin.copy", title: "Copy", chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin))
        XCTAssertEqual(ActionsTab.settingsPage(for: plain), .action(id: "builtin.copy"))

        let group = StubAction(id: "com.openclip.jwt.jwt", title: "JWT", chrome: Self.extensionChrome(package: "com.openclip.jwt", badgeName: "JWT", popupBehavior: .showSubActions))
        XCTAssertEqual(ActionsTab.settingsPage(for: group), .extensionPackage(id: "com.openclip.jwt"), "an extension's group row is the extension")

        let command = StubAction(id: "com.openclip.jwt.jwt.inspect", title: "Inspect", chrome: Self.extensionChrome(package: "com.openclip.jwt", badgeName: "JWT"))
        XCTAssertEqual(ActionsTab.settingsPage(for: command), .action(id: command.id))

        let customGroup = StubAction(id: "custom.abc.group", title: "Mine", chrome: Self.extensionChrome(package: "custom.abc", badgeName: "Mine", popupBehavior: .showSubActions))
        XCTAssertEqual(ActionsTab.settingsPage(for: customGroup), .action(id: customGroup.id), "a custom package is the user's action, not an extension")

        let gated = GatedExtensionAction(packageID: "com.example.gated", title: "Gated", icon: .symbol("lock"), chrome: Self.extensionChrome(package: "com.example.gated"), reason: .notEnabled)
        XCTAssertEqual(ActionsTab.settingsPage(for: gated), .extensionPackage(id: "com.example.gated"))
    }

    // MARK: - Helpers

    private static func extensionChrome(
        package: String,
        badgeName: String? = nil,
        popupBehavior: ActionChrome.PopupBehavior = .perform
    ) -> ActionChrome {
        ActionChrome(
            badge: badgeName.map { .extensionPkg($0) } ?? .none,
            rowStyle: .standard,
            popupBehavior: popupBehavior,
            source: .extensionPkg(packageID: package)
        )
    }
}

private struct StubAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("bolt") }
    let chrome: ActionChrome

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
