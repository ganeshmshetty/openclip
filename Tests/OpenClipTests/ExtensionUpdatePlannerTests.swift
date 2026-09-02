import XCTest
@testable import Core

final class ExtensionUpdatePlannerTests: XCTestCase {
    private func item(_ id: String, version: String?) -> ExtensionItem {
        ExtensionItem(id: id, name: id, description: "", author: "x", icon: "", downloadCount: 0, downloadURL: "https://example.com/\(id).zip", version: version)
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

    // MARK: - ExtensionUpdateBatchResult

    func testBatchCollectAllSucceed() async {
        let ids = ["com.a", "com.b"]
        let result = await ExtensionUpdateBatchResult.collect(packageIDs: ids) { _ in }
        XCTAssertEqual(result.succeeded, ids)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(result.total, 2)
        XCTAssertFalse(result.hasFailures)
    }

    func testBatchCollectAllFail() async {
        let ids = ["com.a", "com.b"]
        let result = await ExtensionUpdateBatchResult.collect(packageIDs: ids) { id in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom \(id)"])
        }
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failed.count, 2)
        XCTAssertEqual(result.failed["com.a"], "boom com.a")
        XCTAssertEqual(result.failed["com.b"], "boom com.b")
        XCTAssertEqual(result.total, 2)
        XCTAssertTrue(result.hasFailures)
    }

    func testBatchCollectMixedResults() async {
        let ids = ["com.a", "com.b", "com.c"]
        let result = await ExtensionUpdateBatchResult.collect(packageIDs: ids) { id in
            if id == "com.b" {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network down"])
            }
        }
        XCTAssertEqual(result.succeeded, ["com.a", "com.c"])
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.failed["com.b"], "network down")
        XCTAssertEqual(result.total, 3)
        XCTAssertTrue(result.hasFailures)
    }

    func testBatchCollectEmpty() async {
        let result = await ExtensionUpdateBatchResult.collect(packageIDs: []) { _ in }
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(result.total, 0)
        XCTAssertFalse(result.hasFailures)
    }

    func testBatchCollectFailureDoesNotAbortRemaining() async {
        let ids = ["com.a", "com.b", "com.c"]
        var attempted: [String] = []
        let result = await ExtensionUpdateBatchResult.collect(packageIDs: ids) { id in
            attempted.append(id)
            if id == "com.a" {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fail"])
            }
        }
        // Even though com.a failed first, com.b and com.c were still attempted.
        XCTAssertEqual(attempted, ids)
        XCTAssertEqual(result.succeeded, ["com.b", "com.c"])
        XCTAssertEqual(result.failed.count, 1)
    }

    func testBatchResultEquatable() {
        let a = ExtensionUpdateBatchResult(succeeded: ["com.a"], failed: ["com.b": "err"])
        let b = ExtensionUpdateBatchResult(succeeded: ["com.a"], failed: ["com.b": "err"])
        let c = ExtensionUpdateBatchResult(succeeded: ["com.a"], failed: ["com.b": "other"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}