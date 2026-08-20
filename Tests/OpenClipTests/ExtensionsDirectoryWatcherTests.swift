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
        let count = await probe.fire(expected: 0)
        XCTAssertEqual(count, 0, "A single differing tick must not fire yet")

        watcher.pollOnce() // second agreeing tick → settle
        let countAfterSettle = await probe.fire(expected: 1)
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
        let count = await probe.fire(expected: 0)
        XCTAssertEqual(count, 0)

        watcher.pollOnce() // tick 3: agrees with tick 2 → settle
        let countAfterSettle = await probe.fire(expected: 1)
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
        let count = await probe.fire(expected: 0)
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
        let count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1)

        // Directory disappears wholesale — must not fire (would be a transient state).
        try FileManager.default.removeItem(at: tempDir)
        watcher.pollOnce()
        let count2 = await probe.fire(expected: 1)
        XCTAssertEqual(count2, 1)
    }

    @MainActor
    func testWatcherRunsDeferredReloadAfterInFlightReloadCompletes() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600)
        defer { watcher.stop() }
        watcher.pollOnce()

        try writeFile("a.sh")
        watcher.pollOnce()
        watcher.pollOnce() // settle → reload 1 starts, suspends in bump()

        // Wait until reload 1 is genuinely in flight (bump suspended).
        let inFlight = await probe.waitForInFlight()
        XCTAssertTrue(inFlight, "reload 1 should be in flight")
        var count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1)

        // A change settles while reload 1 is still running — must not fire a second in parallel.
        try writeFile("b.sh")
        watcher.pollOnce()
        watcher.pollOnce()
        count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1, "No parallel reload while one is in flight")

        // Release reload 1; the deferred reload 2 must then fire exactly once.
        probe.release()
        let finalCount = await probe.fire(expected: 2)
        XCTAssertEqual(finalCount, 2)
        probe.release() // unblock any leftover suspended bump
    }

    /// Counts reload invocations, with an optional suspend gate for testing the reload
    /// coalescing path. MainActor so tests read the count after a yield.
    @MainActor
    private final class ReloadProbe {
        private(set) var fireCount = 0
        private var suspended: [CheckedContinuation<Void, Never>] = []
        private(set) var isInFlight = false

        func bump() async {
            fireCount += 1
            isInFlight = true
            await withCheckedContinuation { suspended.append($0) }
            isInFlight = false
        }

        func waitForInFlight(timeout: TimeInterval = 3.0) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !isInFlight && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return isInFlight
        }

        func fire(expected: Int = 1, timeout: TimeInterval = 2.0) async -> Int {
            let deadline = Date().addingTimeInterval(timeout)
            while fireCount < expected && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            if expected == 0 {
                for _ in 0..<5 {
                    await Task.yield()
                }
            }
            return fireCount
        }

        func release() {
            suspended.forEach { $0.resume() }
            suspended.removeAll()
        }
    }
}
