// ExtensionPackageResolverTests.swift
// OpenClipTests
//
// Unit tests for the pure ExtensionPackageResolver model.
import XCTest
@testable import Core

final class ExtensionPackageResolverTests: XCTestCase {
    private struct DummyAction: Action {
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
        func perform(_ context: ActionContext) async throws -> ActionResult { .success }
    }

    func testEmptyActionsReturnsEmptyPackages() {
        let packages = ExtensionPackageResolver.resolvePackages(from: [], disabledPackages: [])
        XCTAssertTrue(packages.isEmpty)
    }

    func testIgnoresNonExtensionActions() {
        let builtinAction = DummyAction(
            id: "copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let aiAction = DummyAction(
            id: "ai.preset.1",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
        )

        let packages = ExtensionPackageResolver.resolvePackages(from: [builtinAction, aiAction], disabledPackages: [])
        XCTAssertTrue(packages.isEmpty)
    }

    func testResolvesSingleAndMultiActionPackagesWithDeduplication() {
        let pkg1Action1 = DummyAction(
            id: "com.pkg.one.action1",
            chrome: ActionChrome(badge: .extensionPkg("Alpha Package"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.one"))
        )
        let pkg1Action2 = DummyAction(
            id: "com.pkg.one.action2",
            chrome: ActionChrome(badge: .extensionPkg("Alpha Package"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.one"))
        )
        let pkg2Action1 = DummyAction(
            id: "com.pkg.two.action1",
            chrome: ActionChrome(badge: .extensionPkg("Beta Package"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.two"))
        )

        let packages = ExtensionPackageResolver.resolvePackages(from: [pkg1Action1, pkg1Action2, pkg2Action1], disabledPackages: [])
        XCTAssertEqual(packages.count, 2)
        XCTAssertEqual(packages[0].id, "com.pkg.one")
        XCTAssertEqual(packages[0].displayName, "Alpha Package")
        XCTAssertTrue(packages[0].isEnabled)
        XCTAssertEqual(packages[1].id, "com.pkg.two")
        XCTAssertEqual(packages[1].displayName, "Beta Package")
        XCTAssertTrue(packages[1].isEnabled)
    }

    func testDisplayNameFallsBackToPackageIDWhenBadgeAbsentOrEmpty() {
        let actionNoBadge = DummyAction(
            id: "com.pkg.nobadge.action1",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.nobadge"))
        )
        let actionEmptyBadge = DummyAction(
            id: "com.pkg.emptybadge.action1",
            chrome: ActionChrome(badge: .extensionPkg(""), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.emptybadge"))
        )

        let packages = ExtensionPackageResolver.resolvePackages(from: [actionNoBadge, actionEmptyBadge], disabledPackages: [])
        XCTAssertEqual(packages.count, 2)
        let ids = Set(packages.map(\.id))
        XCTAssertTrue(ids.contains("com.pkg.nobadge"))
        XCTAssertTrue(ids.contains("com.pkg.emptybadge"))
        for pkg in packages {
            XCTAssertEqual(pkg.displayName, pkg.id)
        }
    }

    func testIsEnabledReflectsDisabledPackagesSet() {
        let pkg1 = DummyAction(
            id: "com.pkg.one.action",
            chrome: ActionChrome(badge: .extensionPkg("Alpha"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.one"))
        )
        let pkg2 = DummyAction(
            id: "com.pkg.two.action",
            chrome: ActionChrome(badge: .extensionPkg("Beta"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.two"))
        )

        let disabled: Set<String> = ["com.pkg.one"]
        let packages = ExtensionPackageResolver.resolvePackages(from: [pkg1, pkg2], disabledPackages: disabled)

        let alpha = packages.first(where: { $0.id == "com.pkg.one" })
        let beta = packages.first(where: { $0.id == "com.pkg.two" })

        XCTAssertEqual(alpha?.isEnabled, false)
        XCTAssertEqual(beta?.isEnabled, true)
    }

    func testSortsAlphabeticallyByDisplayName() {
        let pkgZ = DummyAction(
            id: "com.pkg.z",
            chrome: ActionChrome(badge: .extensionPkg("Zebra"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.z"))
        )
        let pkgA = DummyAction(
            id: "com.pkg.a",
            chrome: ActionChrome(badge: .extensionPkg("Apple"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.a"))
        )
        let pkgM = DummyAction(
            id: "com.pkg.m",
            chrome: ActionChrome(badge: .extensionPkg("Mango"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.pkg.m"))
        )

        let packages = ExtensionPackageResolver.resolvePackages(from: [pkgZ, pkgA, pkgM], disabledPackages: [])
        XCTAssertEqual(packages.map(\.displayName), ["Apple", "Mango", "Zebra"])
    }
}
