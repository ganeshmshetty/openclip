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

    @MainActor
    func testIdleWatcherDoesNotKeepScanning() async throws {
        let snapshots = SnapshotProbe()
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: tempDir, interval: 0.03)
        defer { watcher.stop() }

        try await waitForScans(1, probe: snapshots)
        try await Task.sleep(for: .milliseconds(250))
        let startupCount = snapshots.count
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(snapshots.count, startupCount, "An idle watcher must not keep scanning")
        XCTAssertEqual(probe.fireCount, 0)

        try writeFile("nested/package.openclipext/scripts/tool.js")
        let count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1, "A real nested filesystem event must reload without manual polling")
        try await Task.sleep(for: .milliseconds(300))
        let settledCount = snapshots.count
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(snapshots.count, settledCount, "Settling checks must stop after reloading")
        XCTAssertEqual(probe.fireCount, 1)
    }

    @MainActor
    func testFilesystemEventsDetectEditsRenamesAndDeletes() async throws {
        try writeFile("package.openclipext/scripts/tool.js")
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: tempDir, interval: 0.03)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try writeFile("package.openclipext/scripts/tool.js", content: "updated atomically")
        var count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1)

        let original = tempDir.appendingPathComponent("package.openclipext/scripts/tool.js")
        let renamed = original.deletingLastPathComponent().appendingPathComponent("renamed.js")
        try FileManager.default.moveItem(at: original, to: renamed)
        count = await probe.fire(expected: 2)
        XCTAssertEqual(count, 2)

        try FileManager.default.removeItem(at: renamed)
        count = await probe.fire(expected: 3)
        XCTAssertEqual(count, 3)
    }

    @MainActor
    func testFilesystemEventsDetectStagedPackageReplacement() async throws {
        try writeFile("package.openclipext/openclip.json", content: "original")
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: tempDir, interval: 0.03)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try writeFile(".install_staging_123/package.openclipext/openclip.json", content: "replacement")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.fireCount, 0, "Staging files must not trigger a reload")

        let package = tempDir.appendingPathComponent("package.openclipext")
        try FileManager.default.removeItem(at: package)
        try FileManager.default.moveItem(
            at: tempDir.appendingPathComponent(".install_staging_123/package.openclipext"), to: package
        )
        let count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.fireCount, 1)
    }

    @MainActor
    func testFilesystemEventsDetectRootRecreationWithoutRetryPolling() async throws {
        try writeFile("original.js")
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: tempDir, interval: 0.03)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try FileManager.default.removeItem(at: tempDir)
        try await waitForScans(2, probe: snapshots)
        try await Task.sleep(for: .milliseconds(200))
        let missingCount = snapshots.count
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(snapshots.count, missingCount, "A missing root must not start endless retries")
        XCTAssertEqual(probe.fireCount, 0, "A transiently missing root must preserve the registry")

        try writeFile("replacement.js")
        let count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1, "Recreating the root must be detected by its ancestor stream")
    }

    @MainActor
    func testFilesystemEventsSurviveWatchedAncestorRemoval() async throws {
        try writeFile("parent/extensions/original.js")
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let root = tempDir.appendingPathComponent("parent/extensions")
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: root, interval: 0.03)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try FileManager.default.removeItem(at: root.deletingLastPathComponent())
        try await waitForScans(2, probe: snapshots)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.fireCount, 0)

        try writeFile("parent/extensions/recreated.js")
        var count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1, "Recreating the watched ancestor must restore hot reload")

        try writeFile("parent/extensions/nested/tool.js")
        count = await probe.fire(expected: 2)
        XCTAssertEqual(count, 2, "Subsequent nested changes must still be observed")
    }

    @MainActor
    func testFilesystemEventsSurviveWatchedAncestorRename() async throws {
        try writeFile("parent/extensions/original.js")
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let root = tempDir.appendingPathComponent("parent/extensions")
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: root, interval: 0.03)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try FileManager.default.moveItem(
            at: root.deletingLastPathComponent(), to: tempDir.appendingPathComponent("retired-parent")
        )
        try await waitForScans(2, probe: snapshots)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.fireCount, 0)

        try writeFile("parent/extensions/recreated.js")
        var count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1, "Replacing a renamed watched ancestor must preserve hot reload")

        try writeFile("parent/extensions/nested/tool.js")
        count = await probe.fire(expected: 2)
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testStopCancelsSettlingAndRestartUsesFreshBaseline() async throws {
        let probe = ReloadProbe()
        let snapshots = SnapshotProbe()
        let watcher = ExtensionsDirectoryWatcher(snapshot: snapshots.build, reload: { probe.record() })
        watcher.start(watching: tempDir, interval: 0.2)
        defer { watcher.stop() }
        try await waitForScans(1, probe: snapshots)

        try writeFile("first.js")
        try await waitForScans(2, probe: snapshots)
        watcher.stop()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(probe.fireCount, 0, "Stop must cancel the pending settle check")
        let stoppedCount = snapshots.count
        try writeFile("while-stopped.js")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(snapshots.count, stoppedCount)

        watcher.start(watching: tempDir, interval: 0.03)
        try await waitForScans(stoppedCount + 1, probe: snapshots)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.fireCount, 0, "Old events must not leak into the restarted session")
        try writeFile("after-restart.js")
        let count = await probe.fire(expected: 1)
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testStopDropsDeferredReload() async throws {
        let probe = ReloadProbe()
        let watcher = ExtensionsDirectoryWatcher(reload: { await probe.bump() })
        watcher.start(watching: tempDir, interval: 3600)
        defer { watcher.stop(); probe.release() }
        watcher.pollOnce()
        try writeFile("first.js")
        watcher.pollOnce()
        watcher.pollOnce()
        let inFlight = await probe.waitForInFlight()
        XCTAssertTrue(inFlight)

        try writeFile("second.js")
        watcher.pollOnce()
        watcher.pollOnce()
        watcher.stop()
        watcher.pollOnce()
        probe.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(probe.fireCount, 1, "Finishing an in-flight reload after stop must not reload again")
    }

    @MainActor
    private func waitForScans(_ count: Int, probe: SnapshotProbe) async throws {
        let deadline = Date().addingTimeInterval(3)
        while probe.count < count && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertGreaterThanOrEqual(probe.count, count)
    }

    private final class SnapshotProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var scans = 0

        var count: Int { lock.withLock { scans } }

        func build(from root: URL) -> ExtensionsSnapshot? {
            let snapshot = ExtensionsSnapshot.build(from: root)
            lock.withLock { scans += 1 }
            return snapshot
        }
    }

    /// Counts reload invocations, with an optional suspend gate for testing the reload
    /// coalescing path. MainActor so tests read the count after a yield.
    @MainActor
    private final class ReloadProbe {
        private(set) var fireCount = 0
        private var suspended: [CheckedContinuation<Void, Never>] = []
        private(set) var isInFlight = false

        func record() {
            fireCount += 1
        }

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
