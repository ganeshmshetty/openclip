// DebugLogReader.swift
// OpenClip
//
// Reads the current process's own unified-log entries for subsystem `com.openclip`
// (the `Log` surface) via OSLogStore, mapping them to DebugLogEntry values.
// Verified mechanism: OSLogStore(scope: .currentProcessIdentifier) readback returns
// the process's live log stream (~1.2 s latency, no drops, privacy fidelity).
import Core
import Foundation
import OSLog

/// Abstraction over a source of `com.openclip` log entries, so callers and tests never
/// touch OSLogStore directly.
protocol LogReading: Sendable {
    /// Returns entries strictly newer than `cursor` (nil = all available since process start),
    /// oldest → newest, capped at `limit`. Returned entries carry `id: 0` (buffer reassigns).
    func read(after cursor: Date?, limit: Int) throws -> [DebugLogEntry]
}

/// Swift forbids default values on protocol requirements, so the `limit` default (2000) lives here:
/// callers through `any LogReading` (e.g. `DebugLogStore.poll`) call `read(after:)` and this
/// extension forwards with the default — class-level defaults don't apply to protocol calls.
extension LogReading {
    func read(after cursor: Date?) throws -> [DebugLogEntry] {
        try read(after: cursor, limit: 2000)
    }
}

/// Production `LogReading` backed by OSLogStore scoped to this process.
/// `@unchecked Sendable` is sound: `store` is created once and only read from the store's
/// single poll queue.
final class UnifiedLogReader: LogReading, @unchecked Sendable {
    private let store: OSLogStore?

    /// Non-throwing: a nil store degrades to empty reads rather than crashing the app.
    init() {
        store = try? OSLogStore(scope: .currentProcessIdentifier)
    }

    func read(after cursor: Date?, limit: Int) throws -> [DebugLogEntry] {
        guard let store else { return [] }
        let position = store.position(date: cursor ?? .distantPast)
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        let entries = try store.getEntries(with: [], at: position, matching: predicate)
        var result: [DebugLogEntry] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            if let cursor, log.date <= cursor { continue }
            result.append(DebugLogEntry(
                date: log.date,
                category: log.category,
                level: DebugLogLevel(log.level),
                message: log.composedMessage
            ))
            if result.count >= limit { break }
        }
        return result
    }
}
