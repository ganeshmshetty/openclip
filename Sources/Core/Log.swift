// Log.swift
// OpenClip
//
// Single logging surface for the OpenClip Core + App targets.
// Broadcasts to Apple's os.Logger and all registered LogSink instances.

import Foundation
import os

/// Severity level of a log entry.
public enum LogLevel: String, Sendable, CaseIterable, Comparable, Equatable, CustomStringConvertible {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    public var displayName: String { rawValue }
    public var description: String { rawValue }

    private var priority: Int {
        switch self {
        case .debug: return 1
        case .info: return 2
        case .notice: return 3
        case .warning: return 4
        case .error: return 5
        case .fault: return 6
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

/// Privacy specifier for string interpolations in log messages.
public enum LogPrivacy: Sendable {
    case `public`
    case `private`
    case auto
}

/// A formatted log message supporting string interpolation with optional privacy annotations.
public struct LogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let stringValue: String

    public init(stringLiteral value: String) {
        self.stringValue = value
    }

    public init(stringValue: String) {
        self.stringValue = stringValue
    }

    public init(stringInterpolation: StringInterpolation) {
        self.stringValue = stringInterpolation.buffer
    }

    public var description: String { stringValue }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var buffer: String = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            buffer.reserveCapacity(literalCapacity + interpolationCount * 16)
        }

        public mutating func appendLiteral(_ literal: String) {
            buffer.append(literal)
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            buffer.append("<private>")
        }

        public mutating func appendInterpolation<T>(_ value: T, privacy: LogPrivacy) {
            switch privacy {
            case .private, .auto:
                buffer.append("<private>")
            case .public:
                buffer.append(String(describing: value))
            }
        }
    }
}

/// Protocol for log consumers (e.g. in-memory buffer, file appender).
public protocol LogSink: Sendable {
    func record(date: Date, category: String, level: LogLevel, message: String)
}

/// A named logging channel that logs to Apple's `os.Logger` and broadcasts to `Log` sinks.
public struct LogChannel: Sendable {
    public let category: String
    private let rawLogger: os.Logger

    public init(category: String) {
        self.category = category
        self.rawLogger = os.Logger(subsystem: Log.subsystem, category: category)
    }

    public func debug(_ message: LogMessage) {
        log(level: .debug, message)
    }

    public func info(_ message: LogMessage) {
        log(level: .info, message)
    }

    public func notice(_ message: LogMessage) {
        log(level: .notice, message)
    }

    public func warning(_ message: LogMessage) {
        log(level: .warning, message)
    }

    public func error(_ message: LogMessage) {
        log(level: .error, message)
    }

    public func fault(_ message: LogMessage) {
        log(level: .fault, message)
    }

    public func log(level: LogLevel, _ message: LogMessage) {
        rawLogger.log(level: level.osLogType, "\(message.stringValue, privacy: .public)")
        Log.record(date: Date(), category: category, level: level, message: message.stringValue)
    }
}

/// Central logging surface. Add a category here (not a brand-new `Logger` instance) whenever a new
/// subsystem starts emitting logs, and keep the table in `docs/logging.md` in step.
public enum Log: Sendable {
    /// Bundle / process identifier shared by every logged message.
    public static let subsystem = "com.openclip"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var sinks: [any LogSink] = []

    public static func addSink(_ sink: any LogSink) {
        lock.lock()
        defer { lock.unlock() }
        sinks.append(sink)
    }

    public static func removeAllSinks() {
        lock.lock()
        defer { lock.unlock() }
        sinks.removeAll()
    }

    public static func record(date: Date, category: String, level: LogLevel, message: String) {
        lock.lock()
        let currentSinks = sinks
        lock.unlock()
        for sink in currentSinks {
            sink.record(date: date, category: category, level: level, message: message)
        }
    }

    // MARK: Core subsystems (settings, rules, policies)
    public static let settings = LogChannel(category: "settings")
    public static let presentation = LogChannel(category: "presentation")
    public static let chrome = LogChannel(category: "chrome")
    public static let factory = LogChannel(category: "factory")
    public static let coordinator = LogChannel(category: "coordinator")
    public static let resultHandler = LogChannel(category: "result-handler")

    // MARK: Runtime owners
    public static let shell = LogChannel(category: "shell")
    public static let js = LogChannel(category: "js")
    public static let selection = LogChannel(category: "selection")
    public static let extensions = LogChannel(category: "extensions")
    public static let ai = LogChannel(category: "ai")
    public static let permissions = LogChannel(category: "permissions")
    public static let icons = LogChannel(category: "icons")
    public static let updates = LogChannel(category: "updates")
}
