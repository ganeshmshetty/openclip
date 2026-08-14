// DebugLogStore.swift
// OpenClip
//
// In-process debug log store backed directly by an in-memory LogSink ring buffer.
// Zero OSLogStore polling, 0ms indexing delay, zero CPU overhead.

import Foundation
import Core

public final class DebugLogStore: @unchecked Sendable {
    public static let shared: DebugLogStore = {
        let buffer = DebugLogBuffer(capacity: 500)
        let store = DebugLogStore(buffer: buffer)
        Log.addSink(buffer)
        return store
    }()

    public let buffer: DebugLogBuffer

    public init(buffer: DebugLogBuffer) {
        self.buffer = buffer
    }

    /// Kept for API compatibility; no background timers are needed.
    public func start() {}
    public func stop() {}

    /// Chronological snapshot (oldest → newest).
    public func snapshot() -> [DebugLogEntry] {
        buffer.snapshot()
    }

    public func entries(matching filter: DebugLogFilter) -> [DebugLogEntry] {
        filter.apply(to: buffer.snapshot())
    }

    public func clear() {
        buffer.clear()
    }
}
