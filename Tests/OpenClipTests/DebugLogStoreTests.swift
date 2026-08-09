import XCTest
@testable import OpenClip

/// Scripted LogReading whose returns are queued; can inject a throw on a chosen call index
/// (0-based). A failing call does NOT consume a batch slot, so a later poll still returns it.
private final class ScriptedLogReader: LogReading, @unchecked Sendable {
    private let lock = NSLock()
    private let batches: [[DebugLogEntry]]
    private let failOnCall: Int?
    private var calls = 0
    private var nextBatch = 0

    init(batches: [[DebugLogEntry]], failOnCall: Int? = nil) {
        self.batches = batches
        self.failOnCall = failOnCall
    }

    func read(after cursor: Date?, limit: Int) throws -> [DebugLogEntry] {
        lock.lock(); defer { lock.unlock() }
        defer { calls += 1 }
        if calls == failOnCall { throw NSError(domain: "ScriptedLogReader", code: 1) }
        guard nextBatch < batches.count else { return [] }
        let batch = batches[nextBatch]
        nextBatch += 1
        return batch
    }
}

private func makeEntry(_ n: Int) -> DebugLogEntry {
    DebugLogEntry(id: 0, date: Date(timeIntervalSince1970: Double(n)), category: "test", level: .notice, message: "m\(n)")
}

final class DebugLogStoreTests: XCTestCase {
    func testPollCollectsEntriesFromReader() {
        let reader = ScriptedLogReader(batches: [[makeEntry(1), makeEntry(2)], [makeEntry(3)]])
        let store = DebugLogStore(reader: reader, buffer: DebugLogBuffer(capacity: 100), pollInterval: 0.05)
        store.start()
        defer { store.stop() }

        // Wait until all three entries have landed (poll 0 → [1,2], poll 1 → [3]).
        let deadline = Date().addingTimeInterval(2)
        while store.snapshot().count < 3 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(store.snapshot().map(\.message), ["m1", "m2", "m3"])
    }

    func testReaderErrorDoesNotKillPolling() {
        let reader = ScriptedLogReader(batches: [[makeEntry(1)], [makeEntry(2)]], failOnCall: 1)
        let store = DebugLogStore(reader: reader, buffer: DebugLogBuffer(capacity: 100), pollInterval: 0.05)
        store.start()
        defer { store.stop() }

        // poll 0 → [m1], poll 1 → throws, poll 2 → [m2]; wait until both have landed.
        let deadline = Date().addingTimeInterval(2)
        while store.snapshot().count < 2 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(store.snapshot().map(\.message), ["m1", "m2"])
    }

    func testStopHaltsFurtherReads() {
        let reader = ScriptedLogReader(batches: [[makeEntry(1)], [makeEntry(2)]])
        let store = DebugLogStore(reader: reader, buffer: DebugLogBuffer(capacity: 100), pollInterval: 0.1)
        store.start()
        defer { store.stop() }

        // Wait deterministically until the first poll has landed (first tick at ~0.1s), then stop.
        let deadline = Date().addingTimeInterval(2)
        while store.snapshot().isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        store.stop()

        Thread.sleep(forTimeInterval: 0.25) // a second tick (0.2s cadence) would have read batch 2
        XCTAssertEqual(store.snapshot().map(\.message), ["m1"])
    }

    func testEntriesMatchingAppliesFilter() {
        let reader = ScriptedLogReader(batches: [[makeEntry(1), makeEntry(2)]])
        let store = DebugLogStore(reader: reader, buffer: DebugLogBuffer(capacity: 100), pollInterval: 0.05)
        store.start()
        defer { store.stop() }

        let deadline = Date().addingTimeInterval(2)
        while store.snapshot().count < 2 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let errorOnly = store.entries(matching: DebugLogFilter(level: .error))
        XCTAssertTrue(errorOnly.isEmpty)
        let noticeOnly = store.entries(matching: DebugLogFilter(level: .notice))
        XCTAssertEqual(noticeOnly.map(\.message), ["m2", "m1"]) // newest first
    }
}