import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionsDirectoryWatcherTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeFile(_ relativePath: String, content: String = "#!/bin/sh\necho hi") throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Snapshot

    func testSnapshotIsStableWhenNothingChanges() throws {
        try writeFile("manifest_ext.openclipext/openclip.json")
        try writeFile("tool.sh")

        let first = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        let second = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        XCTAssertEqual(first, second, "A rebuild with no changes must produce an equal snapshot")
    }

    func testSnapshotDetectsAddedRemovedAndEditedFiles() throws {
        try writeFile("a.sh")

        let base = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))

        try writeFile("b.sh")
        let afterAdd = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        XCTAssertNotEqual(base, afterAdd, "Adding a file must change the snapshot")

        try writeFile("a.sh", content: "#!/bin/sh\necho changed")
        let afterEdit = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        XCTAssertNotEqual(base, afterEdit, "Editing a file must change the snapshot")

        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("b.sh"))
        let afterRemove = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        XCTAssertNotEqual(base, afterRemove, "Removing a file must change the snapshot")
    }

    func testSnapshotIgnoresHiddenItems() throws {
        let before = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))

        try writeFile(".install_staging_123/package/openclip.json")
        try writeFile(".DS_Store")

        let after = try XCTUnwrap(ExtensionsSnapshot.build(from: tempDir))
        XCTAssertEqual(before, after, "Hidden/staging files must not change the snapshot")
    }

    func testSnapshotNilWhenDirectoryMissing() throws {
        let missing = tempDir.appendingPathComponent("does_not_exist")
        XCTAssertNil(ExtensionsSnapshot.build(from: missing))
    }

    // MARK: - Watcher settle logic

    @MainActor
    func testWatcherFiresOnceAfterChangeSettles() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600) // far-future, never fires on its own
        defer { watcher.stop() }
        watcher.pollOnce() // establish the baseline snapshot

        try writeFile("manifest_ext.openclipext/openclip.json")

        watcher.pollOnce() // first differing tick
        let count = await probe.settle()
        XCTAssertEqual(count, 0, "A single differing tick must not fire yet")

        watcher.pollOnce() // second agreeing tick → settle
        let countAfterSettle = await probe.settle()
        XCTAssertEqual(countAfterSettle, 1)
    }

    @MainActor
    func testWatcherDoesNotFireWhileTreeKeepsChanging() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600)
        defer { watcher.stop() }
        watcher.pollOnce()

        try writeFile("a.sh")
        watcher.pollOnce() // tick 1: changed, pending

        try writeFile("b.sh") // still mid-change
        watcher.pollOnce() // tick 2: pending slides forward, not settled
        let count = await probe.settle()
        XCTAssertEqual(count, 0)

        watcher.pollOnce() // tick 3: agrees with tick 2 → settle
        let countAfterSettle = await probe.settle()
        XCTAssertEqual(countAfterSettle, 1)
    }

    @MainActor
    func testWatcherDoesNotFireWithoutChanges() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600)
        defer { watcher.stop() }
        watcher.pollOnce()

        watcher.pollOnce()
        watcher.pollOnce()
        let count = await probe.settle()
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testWatcherDoesNotFireWhenDirectoryGoesMissing() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600)
        defer { watcher.stop() }
        watcher.pollOnce()

        try writeFile("a.sh")
        watcher.pollOnce()
        watcher.pollOnce()
        let count = await probe.settle()
        XCTAssertEqual(count, 1)

        // Directory disappears wholesale — must not fire (would be a transient state).
        try FileManager.default.removeItem(at: tempDir)
        watcher.pollOnce()
        let count2 = await probe.settle()
        XCTAssertEqual(count2, 1)
    }

    /// Counts reload invocations. `bump` is MainActor so reading the count after a
    /// `Task.sleep(for: .milliseconds(50))` guarantees the reload Task has run.
    @MainActor
    private final class ReloadProbe {
        private(set) var fireCount = 0

        func bump() async {
            fireCount += 1
        }

        func settle() async -> Int {
            try? await Task.sleep(for: .milliseconds(50))
            return fireCount
        }
    }
}