// DebugLogBuffer.swift
// OpenClip
//
// Thread-safe fixed-capacity ring buffer for recent Log entries.
// Conforms to LogSink to receive direct in-memory broadcasts from Log.

import Foundation
import Core

/// Thread-safe, capacity-capped log entry store. Oldest entries are evicted on overflow.
/// Safe to call from any queue (NSLock-guarded).
public final class DebugLogBuffer: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DebugLogEntry] = []
    private var nextID = 0
    private let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public func record(date: Date, category: String, level: LogLevel, message: String) {
        append(DebugLogEntry(id: 0, date: date, category: category, level: level, message: message))
    }

    /// Appends an entry, assigning a stable sequential `id`, evicting the oldest beyond capacity.
    @discardableResult
    public func append(_ entry: DebugLogEntry) -> DebugLogEntry {
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

    public func append(contentsOf entries: [DebugLogEntry]) {
        for entry in entries { append(entry) }
    }

    /// Chronological snapshot (oldest → newest).
    public func snapshot() -> [DebugLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }
}
