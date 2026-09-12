// SettingsRouterTests.swift
// OpenClipTests
//
// Pins the settings window's navigation model: the router's path and history (what the toolbar's
// back/forward arrows walk), the sidebar's search matching, how installed extensions are derived
// from the action catalog for the sidebar's second group, where every kind of action's settings
// live, and what the toolbar's trailing switch and ellipsis menu offer per page.

import XCTest
import Combine
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
        router.select(.customize)
        router.push(.action(id: "builtin.search"))
        router.select(.ai)

        XCTAssertEqual(router.path, [.ai])
        XCTAssertEqual(router.history, [[.general], [.customize], [.customize, .action(id: "builtin.search")], [.ai]])
        XCTAssertTrue(router.canGoBack)
        XCTAssertFalse(router.canGoForward)
    }

    func testPushDrillsInAndPopComesBackOut() {
        let router = SettingsRouter()
        router.select(.customize)
        router.push(.action(id: "a"))
        XCTAssertEqual(router.path, [.customize, .action(id: "a")])
        XCTAssertEqual(router.sidebarPage, .customize, "the sidebar keeps the page the editor was reached from")
        XCTAssertEqual(router.currentPage, .action(id: "a"))

        router.pop()
        XCTAssertEqual(router.path, [.customize])
        XCTAssertEqual(router.history.last, [.customize], "pop is a navigation of its own, so it is recorded")
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
        router.select(.customize)
        router.push(.action(id: "a"))
        router.pushIconPicker(writingTo: .constant("bolt"))
        XCTAssertEqual(router.path.count, 3)

        router.push(.action(id: "a"))
        XCTAssertEqual(router.path, [.customize, .action(id: "a")])
    }

    func testBackAndForwardWalkTheHistory() {
        let router = SettingsRouter()
        router.select(.customize)
        router.push(.action(id: "a"))
        router.select(.about)

        router.goBack()
        XCTAssertEqual(router.path, [.customize, .action(id: "a")])
        XCTAssertTrue(router.canGoForward)

        router.goBack()
        XCTAssertEqual(router.path, [.customize])
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
        router.select(.customize)
        router.select(.about)
        router.goBack()
        XCTAssertTrue(router.canGoForward)

        router.select(.shortcuts)
        XCTAssertFalse(router.canGoForward)
        XCTAssertEqual(router.history, [[.general], [.customize], [.shortcuts]])
    }

    func testShowingTheCurrentPathAgainRecordsNothing() {
        let router = SettingsRouter()
        router.select(.customize)
        router.select(.customize)
        router.show(path: [.customize])
        XCTAssertEqual(router.history, [[.general], [.customize]])
    }

    func testSelectingTheSidebarPageWhileDrilledInReturnsToItsTop() {
        let router = SettingsRouter()
        router.select(.customize)
        router.push(.action(id: "a"))
        router.select(.customize)
        XCTAssertEqual(router.path, [.customize])
    }

    func testHistoryIsCapped() {
        let router = SettingsRouter()
        for step in 0..<(SettingsRouter.historyLimit + 40) {
            router.select(step % 2 == 0 ? .customize : .general)
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

        XCTAssertEqual(router.path, [.extensionPackage(id: "com.example.tool"), .action(id: action.id)],
                       "an extension's command is configured under its extension")
        XCTAssertEqual(router.configurationRequest(for: action.id), request)
        router.clearConfigurationRequest(for: action.id)
        XCTAssertNil(router.configurationRequest(for: action.id))
    }

    func testIconPickerKeepsTheBindingItWasHanded() {
        let router = SettingsRouter()
        var symbol = "bolt"
        let binding = Binding(get: { symbol }, set: { symbol = $0 })
        router.select(.customize)
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

    func testTheSidebarListsWhatShippedBeforeWhatWasInstalled() {
        // Deliberately shuffled, and with names that would interleave under a plain A-Z sort.
        let rows = [
            SettingsSidebarRow(page: .extensionPackage(id: "com.a.appwrite"), title: "Appwrite", tile: .symbol("puzzlepiece.extension.fill", tint: .gray)),
            SettingsSidebarRow(page: .builtinAction(id: "builtin.paste"), title: "Paste", tile: .symbol("bolt.fill", tint: .gray)),
            SettingsSidebarRow(page: .customActions, title: "Custom Actions", tile: .symbol("wand.and.stars", tint: .mint)),
            SettingsSidebarRow(page: .extensionPackage(id: "com.z.jwt"), title: "JWT", tile: .symbol("puzzlepiece.extension.fill", tint: .gray)),
            SettingsSidebarRow(page: .builtinAction(id: "builtin.copy"), title: "Copy", tile: .symbol("bolt.fill", tint: .gray)),
            SettingsSidebarRow(systemPage: .ai),
        ]

        XCTAssertEqual(SettingsSidebarOrder.sorted(rows).map(\.title), [
            "AI",              // OpenClip's own, first
            "Copy", "Paste",   // then the built-in actions, alphabetically
            "Custom Actions",  // then what the user wrote here
            "Appwrite", "JWT", // then what the user installed, alphabetically
        ])
    }

    func testTheSidebarOrderIsStableForRowsOfTheSameKind() {
        let rows = [
            SettingsSidebarRow(page: .extensionPackage(id: "b"), title: "Übersicht", tile: .symbol("x", tint: .gray)),
            SettingsSidebarRow(page: .extensionPackage(id: "a"), title: "Alpha", tile: .symbol("x", tint: .gray)),
            SettingsSidebarRow(page: .extensionPackage(id: "c"), title: "alpha two", tile: .symbol("x", tint: .gray)),
        ]
        XCTAssertEqual(SettingsSidebarOrder.sorted(rows).map(\.title), ["Alpha", "alpha two", "Übersicht"],
                       "names sort the way the Finder sorts them, not by code point")
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

    func testAOneCommandPackageIsStillAnExtensionWithItsOneCommand() throws {
        // Not every package groups its commands behind one icon; a package can contribute a
        // single top-level action, and it gets the same page with one row in it.
        let package = "com.openclip.shortenlink"
        let action = StubAction(
            id: "\(package).action.0",
            title: "Shorten Link",
            chrome: Self.extensionChrome(package: package, badgeName: "Shorten Link")
        )

        let info = try XCTUnwrap(InstalledExtensionInfo.info(for: package, in: [action]))
        XCTAssertEqual(info.name, "Shorten Link")
        XCTAssertFalse(info.isGroup, "no group container, so nothing to rename in the popup bar")
        XCTAssertNil(info.containerActionID)
        XCTAssertEqual(info.commands.map(\.id), [action.id], "its one command is listed like any other")
        XCTAssertEqual(info.uninstallActionID, action.id, "and it is what the uninstall matches on")

        XCTAssertEqual(InstalledExtensionInfo.all(from: [action]).map(\.packageID), [package])
        XCTAssertEqual(SettingsDestination.path(for: action),
                       [.extensionPackage(id: package), .action(id: action.id)],
                       "opening the command keeps its extension's page one step back")
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

    // MARK: - Where an action's settings live

    func testEveryKindOfActionHasOneHome() {
        let builtin = StubAction(id: "builtin.copy", title: "Copy", chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin))
        XCTAssertEqual(SettingsDestination.path(for: builtin), [.builtinAction(id: "builtin.copy")], "a built-in is a sidebar row of its own")

        let group = StubAction(id: "com.openclip.jwt.jwt", title: "JWT", chrome: Self.extensionChrome(package: "com.openclip.jwt", badgeName: "JWT", popupBehavior: .showSubActions))
        XCTAssertEqual(SettingsDestination.path(for: group), [.extensionPackage(id: "com.openclip.jwt")], "an extension's group row is the extension")

        let command = StubAction(id: "com.openclip.jwt.jwt.inspect", title: "Inspect", chrome: Self.extensionChrome(package: "com.openclip.jwt", badgeName: "JWT"))
        XCTAssertEqual(SettingsDestination.path(for: command), [.extensionPackage(id: "com.openclip.jwt"), .action(id: command.id)], "a command sits under its extension")

        let custom = StubAction(id: "custom.abc123", title: "Mine", chrome: ActionChrome(badge: .custom, rowStyle: .standard, popupBehavior: .perform, source: .custom))
        XCTAssertEqual(SettingsDestination.path(for: custom), [.customActions, .action(id: "custom.abc123")])
        XCTAssertTrue(SettingsDestination.isCustomAction(custom))

        let manifestBackedCustom = StubAction(id: "custom.def456", title: "Snippet", chrome: Self.extensionChrome(package: "custom.def456", badgeName: "Snippet"))
        XCTAssertEqual(SettingsDestination.path(for: manifestBackedCustom), [.customActions, .action(id: "custom.def456")], "a custom action stored as a manifest package is still the user's action")
        XCTAssertTrue(SettingsDestination.isCustomAction(manifestBackedCustom))

        let customGroup = StubAction(id: "vgroup.abc", title: "My Group", chrome: ActionChrome(badge: .none, rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .custom))
        XCTAssertEqual(SettingsDestination.path(for: customGroup), [.customize, .action(id: "vgroup.abc")], "groups are made and edited on Customize")
        XCTAssertFalse(SettingsDestination.isCustomAction(customGroup))

        let gated = GatedExtensionAction(packageID: "com.example.gated", title: "Gated", icon: .symbol("lock"), chrome: Self.extensionChrome(package: "com.example.gated"), reason: .notEnabled)
        XCTAssertEqual(SettingsDestination.path(for: gated), [.extensionPackage(id: "com.example.gated")])

        XCTAssertEqual(SettingsDestination.path(forPackage: "com.example.multi"), [.extensionPackage(id: "com.example.multi")])
    }

    // MARK: - Toolbar accessories

    func testExtensionMenuOffersReadmeAndFinderOnlyWhenTheyExist() {
        let full = SettingsToolbarAccessories.extensionMenuItems(.init(hasReadme: true, hasFolder: true))
        XCTAssertEqual(full.map(\.id), [
            SettingsToolbarCommand.extensionReadme,
            SettingsToolbarCommand.extensionFinder,
            "extension.separator",
            SettingsToolbarCommand.extensionUninstall,
        ])
        XCTAssertEqual(full.last?.role, .destructive, "uninstall is the red one")

        let noReadme = SettingsToolbarAccessories.extensionMenuItems(.init(hasReadme: false, hasFolder: true))
        XCTAssertEqual(noReadme.map(\.id), [
            SettingsToolbarCommand.extensionFinder,
            "extension.separator",
            SettingsToolbarCommand.extensionUninstall,
        ])

        let bare = SettingsToolbarAccessories.extensionMenuItems(.init(hasReadme: false, hasFolder: false))
        XCTAssertEqual(bare.map(\.id), [SettingsToolbarCommand.extensionUninstall],
                       "no separator when there is nothing above it")
        XCTAssertFalse(bare.contains { $0.isSeparator })
    }

    func testStoreMenuHoldsInstallAndRefreshAndGreysRefreshWhileItRuns() throws {
        let idle = SettingsToolbarAccessories.storeMenuItems(isRefreshing: false)
        XCTAssertEqual(idle.map(\.id), [
            SettingsToolbarCommand.storeInstallFile,
            SettingsToolbarCommand.storeRefresh,
        ], "installing a package from disk belongs to the Store, not to Customize")
        XCTAssertTrue(idle.allSatisfy(\.isEnabled))
        XCTAssertFalse(idle.contains { $0.role == .destructive })

        let busy = SettingsToolbarAccessories.storeMenuItems(isRefreshing: true)
        XCTAssertTrue(try XCTUnwrap(busy.first { $0.id == SettingsToolbarCommand.storeInstallFile }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(busy.first { $0.id == SettingsToolbarCommand.storeRefresh }).isEnabled,
                       "a refresh already running must not be startable again")
    }

    func testActionMenuMatchesWhatTheActionAllows() {
        let builtin = SettingsToolbarAccessories.actionMenuItems(.init(canDuplicate: false, canDelete: false))
        XCTAssertTrue(builtin.isEmpty, "a built-in has no page-level actions, so no ellipsis at all")

        let command = SettingsToolbarAccessories.actionMenuItems(.init(canDuplicate: true, canDelete: false))
        XCTAssertEqual(command.map(\.id), [SettingsToolbarCommand.actionDuplicate])

        let custom = SettingsToolbarAccessories.actionMenuItems(.init(canDuplicate: true, canDelete: true))
        XCTAssertEqual(custom.map(\.id), [
            SettingsToolbarCommand.actionDuplicate,
            "action.separator",
            SettingsToolbarCommand.actionDelete,
        ])
        XCTAssertEqual(custom.last?.role, .destructive)

        let deleteOnly = SettingsToolbarAccessories.actionMenuItems(.init(canDuplicate: false, canDelete: true))
        XCTAssertEqual(deleteOnly.map(\.id), [SettingsToolbarCommand.actionDelete])
    }

    func testADestructiveConfirmationWaitsForTheRedButton() throws {
        let router = SettingsRouter()
        var uninstalled = false
        router.confirmDestructive(title: "Uninstall JWT?", message: "Gone for good.", confirmTitle: "Uninstall") {
            uninstalled = true
        }

        let notice = try XCTUnwrap(router.notice)
        XCTAssertEqual(notice.style, .destructiveConfirmation)
        XCTAssertEqual(notice.confirmTitle, "Uninstall")
        XCTAssertTrue(notice.isConfirmation)
        XCTAssertFalse(uninstalled, "posting the question must not do the thing")

        router.dismissNotice()
        XCTAssertFalse(uninstalled, "dismissing is a no")
        XCTAssertNil(router.notice)

        router.confirmDestructive(title: "Uninstall JWT?", message: "Gone for good.", confirmTitle: "Uninstall") {
            uninstalled = true
        }
        router.confirmNotice()
        XCTAssertTrue(uninstalled)
        XCTAssertNil(router.notice, "answering takes the banner down")
    }

    func testAPlainNoticeHasNothingToConfirm() throws {
        let router = SettingsRouter()
        router.notifyError(title: "Remove Failed", message: "Nope")
        XCTAssertFalse(try XCTUnwrap(router.notice).isConfirmation)
        router.confirmNotice()
        XCTAssertNil(router.notice, "confirming a plain notice just dismisses it")
    }

    func testPageCommandsReachTheSubscribedPage() {
        let router = SettingsRouter()
        var received: [String] = []
        let token = router.pageCommands.sink { received.append($0) }
        router.pageCommands.send(SettingsToolbarCommand.actionDuplicate)
        router.pageCommands.send(SettingsToolbarCommand.actionDelete)
        token.cancel()
        XCTAssertEqual(received, [SettingsToolbarCommand.actionDuplicate, SettingsToolbarCommand.actionDelete])
    }

    // MARK: - Tints

    func testAGeneratedExtensionTintIsNeverBlue() {
        // Blue belongs to OpenClip's own rows, so nothing installed may land in that band however
        // its identifier hashes.
        var seen = Set<Int>()
        for index in 0..<5_000 {
            let hue = SettingsTint.hue(for: "com.example.extension.\(index)")
            XCTAssertFalse(SettingsTint.reservedBlueHues.contains(hue),
                           "id \(index) landed on hue \(hue), inside the reserved band")
            XCTAssertTrue((0..<360).contains(hue), "hue \(hue) is not a hue")
            seen.insert(hue)
        }
        XCTAssertGreaterThan(seen.count, 100, "the palette must still spread, not pile up on a few hues")

        // The real identifiers this Mac has installed, and the empty case.
        for id in ["io.appwrite.openclip", "com.openclip.jwt", "com.openclip.harper", "com.openclip.urlquery", ""] {
            XCTAssertFalse(SettingsTint.reservedBlueHues.contains(SettingsTint.hue(for: id)), id)
        }
    }

    func testAnExtensionKeepsTheSameTintEveryTime() {
        let first = SettingsTint.hue(for: "com.openclip.jwt")
        let again = SettingsTint.hue(for: "com.openclip.jwt")
        XCTAssertEqual(first, again, "a package's colour must not move between launches")
        XCTAssertNotEqual(first, SettingsTint.hue(for: "com.openclip.urlquery"))
    }

    func testTheSidebarsThreeKindsOfRowAreThreeColours() {
        for page in SettingsPage.systemPages {
            XCTAssertEqual(page.tint, SettingsTint.system, "\(page.id) is the app's own settings, so grey")
        }
        XCTAssertEqual(SettingsPage.ai.tint, SettingsTint.openClip)
        XCTAssertEqual(SettingsPage.customActions.tint, SettingsTint.openClip)
        XCTAssertEqual(SettingsPage.builtinAction(id: "builtin.copy").tint, SettingsTint.openClip)

        let installed = SettingsPage.extensionPackage(id: "com.openclip.jwt").tint
        XCTAssertNotEqual(installed, SettingsTint.openClip, "an extension never wears the brand colour")
        XCTAssertNotEqual(installed, SettingsTint.system)
    }

    // MARK: - Naming a group made by dropping

    func testADroppedGroupTakesThePlainNameUntilItIsTaken() {
        let numbered: (Int) -> String = { "New Group \($0)" }

        XCTAssertEqual(
            ActionsOutlineCoordinator.uniqueGroupTitle(base: "New Group", numbered: numbered, existing: []),
            "New Group"
        )
        XCTAssertEqual(
            ActionsOutlineCoordinator.uniqueGroupTitle(base: "New Group", numbered: numbered, existing: ["Writing"]),
            "New Group"
        )
        XCTAssertEqual(
            ActionsOutlineCoordinator.uniqueGroupTitle(base: "New Group", numbered: numbered, existing: ["New Group"]),
            "New Group 2"
        )
        XCTAssertEqual(
            ActionsOutlineCoordinator.uniqueGroupTitle(
                base: "New Group",
                numbered: numbered,
                existing: ["New Group", "New Group 2", "New Group 3"]
            ),
            "New Group 4",
            "it counts past every number already in use"
        )
        XCTAssertEqual(
            ActionsOutlineCoordinator.uniqueGroupTitle(
                base: "New Group",
                numbered: numbered,
                existing: ["New Group", "New Group 3"]
            ),
            "New Group 2",
            "and fills the first gap rather than always going to the end"
        )
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
