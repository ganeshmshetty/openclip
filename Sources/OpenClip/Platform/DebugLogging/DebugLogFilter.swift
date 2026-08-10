// DebugLogFilter.swift
// OpenClip
//
// Pure filter over captured log entries: category, level, and newest-first count cap.
import Foundation

/// Newest-first filter for the debug log store. `nil` fields mean "no constraint";
/// `count == nil || count == 0` means "no cap".
struct DebugLogFilter: Equatable {
    var category: String?
    var level: DebugLogLevel?
    var count: Int?

    func apply(to entries: [DebugLogEntry]) -> [DebugLogEntry] {
        var result = entries.filter { entry in
            (category == nil || entry.category == category) &&
            (level == nil || entry.level == level)
        }
        result.reverse()
        if let count, count > 0, result.count > count {
            result.removeSubrange(count...)
        }
        return result
    }
}
