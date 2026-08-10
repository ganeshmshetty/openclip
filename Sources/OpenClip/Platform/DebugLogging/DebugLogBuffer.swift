// DebugLogBuffer.swift
// OpenClip
//
// Thread-safe fixed-capacity ring buffer for recent UnifiedLog entries.
// Sole storage for the in-process debug log store (App target only).
import Foundation

/// Thread-safe, capacity-capped log entry store. Oldest entries are evicted on overflow.
/// Safe to call from any queue (NSLock-guarded).
final class DebugLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DebugLogEntry] = []
    private var nextID = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Appends an entry, assigning a stable sequential `id`, evicting the oldest beyond capacity.
    @discardableResult
    func append(_ entry: DebugLogEntry) -> DebugLogEntry {
        lock.lock(); defer { lock.unlock() }
        let ided = DebugLogEntry(
            id: nextID,
            date: entry.date,
            category: entry.category,
            level: entry.level,
            message: entry.message
        )
        nextID += 1
        storage.append(ided)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        return ided
    }

    func append(contentsOf entries: [DebugLogEntry]) {
        for entry in entries { append(entry) }
    }

    /// Chronological snapshot (oldest → newest).
    func snapshot() -> [DebugLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }
}
