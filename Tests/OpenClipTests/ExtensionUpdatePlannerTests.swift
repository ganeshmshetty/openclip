import XCTest
@testable import Core

final class ExtensionUpdatePlannerTests: XCTestCase {
    private func item(_ id: String, version: String?) -> ExtensionItem {
        ExtensionItem(id: id, name: id, description: "", author: "x", icon: "", category: "Utilities", downloadCount: 0, downloadURL: "https://example.com/\(id).zip", version: version)
    }

    func testNewerStoreVersionMarksUpdatable() {
        let items = [item("com.a", version: "1.2.0")]
        let installed = [InstalledPackageVersion(packageID: "com.a", installedVersion: "1.1.0", source: "store")]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), ["com.a"])
    }

    func testEqualOrOlderIsNotUpdatable() {
        let items = [item("com.a", version: "1.1.0"), item("com.b", version: "1.0.0")]
        let installed = [
            InstalledPackageVersion(packageID: "com.a", installedVersion: "1.1.0", source: "store"),
            InstalledPackageVersion(packageID: "com.b", installedVersion: "2.0.0", source: "store")
        ]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), [])
    }

    func testMissingVersionOnEitherSideIsNotUpdatable() {
        let items = [item("com.a", version: nil), item("com.b", version: "1.2.0")]
        let installed = [
            InstalledPackageVersion(packageID: "com.a", installedVersion: "1.0.0", source: "store"),
            InstalledPackageVersion(packageID: "com.b", installedVersion: nil, source: "store")
        ]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), [])
    }

    func testLocalSourceIsNeverUpdatable() {
        let items = [item("com.a", version: "2.0.0")]
        let installed = [InstalledPackageVersion(packageID: "com.a", installedVersion: "1.0.0", source: "local")]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), [])
    }

    func testDuplicateStoreIDsDoNotCrashAndLastWins() {
        let items = [item("com.a", version: "1.2.0"), item("com.a", version: "1.0.0"), item("com.a", version: "2.0.0")]
        let installed = [InstalledPackageVersion(packageID: "com.a", installedVersion: "1.1.0", source: "store")]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), ["com.a"])
    }

    func testDuplicateStoreIDsWithOnlyStaleLastEntryIsNotUpdatable() {
        let items = [item("com.a", version: "2.0.0"), item("com.a", version: "1.0.0")]
        let installed = [InstalledPackageVersion(packageID: "com.a", installedVersion: "1.1.0", source: "store")]
        XCTAssertEqual(ExtensionUpdatePlanner.updatablePackageIDs(storeItems: items, installed: installed), [])
    }
}