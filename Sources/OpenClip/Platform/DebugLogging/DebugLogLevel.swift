// DebugLogLevel.swift
// OpenClip
//
// Severity level of a captured debug log entry.
// Bridges to Core.LogLevel and provides OSLog compatibility initializer for tests.

import OSLog
import Core

public typealias DebugLogLevel = LogLevel

extension LogLevel {
    public init(_ level: OSLogEntryLog.Level) {
        switch level {
        case .undefined: self = .debug
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .error: self = .error
        case .fault: self = .fault
        @unknown default: self = .debug
        }
    }
}
