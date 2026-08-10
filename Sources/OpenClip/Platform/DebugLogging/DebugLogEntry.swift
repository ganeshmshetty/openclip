// DebugLogEntry.swift
// OpenClip
//
// One captured log line: timestamp, subsystem category, level, and decoded message.
import Foundation

/// A single captured `Log` line. `id` is a per-process sequential index assigned at
/// append time by `DebugLogBuffer`; readers pass `id: 0`.
struct DebugLogEntry: Equatable {
    let id: Int
    let date: Date
    let category: String
    let level: DebugLogLevel
    let message: String

    init(id: Int = 0, date: Date, category: String, level: DebugLogLevel, message: String) {
        self.id = id
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }
}
