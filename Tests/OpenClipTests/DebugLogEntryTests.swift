import XCTest
import OSLog
@testable import OpenClip

final class DebugLogEntryTests: XCTestCase {
    func testLevelMapsFromOSLogEntryLevel() {
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 0) ?? .undefined), .undefined)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 1) ?? .undefined), .debug)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 2) ?? .undefined), .info)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 3) ?? .undefined), .notice)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 4) ?? .undefined), .error)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 5) ?? .undefined), .fault)
        XCTAssertEqual(DebugLogLevel(OSLogEntryLog.Level(rawValue: 99) ?? .undefined), .undefined)
    }

    func testLevelDisplayNames() {
        XCTAssertEqual(DebugLogLevel.error.displayName, "error")
        XCTAssertEqual(DebugLogLevel.debug.displayName, "debug")
    }

    func testLevelIsComparableBySeverity() {
        XCTAssertLessThan(DebugLogLevel.debug, DebugLogLevel.error)
        XCTAssertLessThan(DebugLogLevel.notice, DebugLogLevel.fault)
    }
}
