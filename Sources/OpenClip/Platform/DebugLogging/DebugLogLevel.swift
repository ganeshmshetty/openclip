// DebugLogLevel.swift
// OpenClip
//
// Severity level of a captured debug log entry, mirrored from OSLogEntryLog.Level.
import OSLog

/// Severity of a captured `Log` entry. `rawValue` matches `OSLogEntryLog.Level`.
enum DebugLogLevel: Int, CaseIterable, Comparable, Equatable {
    case undefined
    case debug
    case info
    case notice
    case error
    case fault

    init(_ level: OSLogEntryLog.Level) {
        self = DebugLogLevel(rawValue: level.rawValue) ?? .undefined
    }

    static func < (lhs: DebugLogLevel, rhs: DebugLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        }
    }
}
