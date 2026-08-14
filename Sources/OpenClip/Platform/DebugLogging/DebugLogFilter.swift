// DebugLogFilter.swift
// OpenClip
//
// Pure filter over captured log entries: category, level, and newest-first count cap.
import Foundation
import Core

/// Newest-first filter for the debug log store. `nil` fields mean "no constraint";
/// `count == nil || count == 0` means "no cap".
public struct DebugLogFilter: Equatable, Sendable {
    public var category: String?
    public var level: DebugLogLevel?
    public var count: Int?

    public init(category: String? = nil, level: DebugLogLevel? = nil, count: Int? = nil) {
        self.category = category
        self.level = level
        self.count = count
    }

    public func apply(to entries: [DebugLogEntry]) -> [DebugLogEntry] {
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
