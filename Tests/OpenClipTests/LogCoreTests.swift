import XCTest
@testable import Core

private final class TestLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    var records: [(date: Date, category: String, level: LogLevel, message: String)] = []

    func record(date: Date, category: String, level: LogLevel, message: String) {
        lock.lock()
        defer { lock.unlock() }
        records.append((date: date, category: category, level: level, message: message))
    }

    func getRecords() -> [(date: Date, category: String, level: LogLevel, message: String)] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

final class LogCoreTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            Log.removeAllSinks()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            Log.removeAllSinks()
        }
        try await super.tearDown()
    }

    func testLogLevelComparisonAndDisplayName() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.notice)
        XCTAssertLessThan(LogLevel.notice, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.fault)

        XCTAssertEqual(LogLevel.debug.displayName, "debug")
        XCTAssertEqual(LogLevel.error.displayName, "error")
        XCTAssertEqual(LogLevel.notice.displayName, "notice")
    }

    func testLogBroadcastsToRegisteredSinks() {
        let sink1 = TestLogSink()
        let sink2 = TestLogSink()
        Log.addSink(sink1)
        Log.addSink(sink2)

        Log.settings.info("Test settings message")
        Log.extensions.error("Test error \(123, privacy: .public)")

        let r1 = sink1.getRecords()
        let r2 = sink2.getRecords()

        XCTAssertEqual(r1.count, 2)
        XCTAssertEqual(r2.count, 2)

        XCTAssertEqual(r1[0].category, "settings")
        XCTAssertEqual(r1[0].level, .info)
        XCTAssertEqual(r1[0].message, "Test settings message")

        XCTAssertEqual(r1[1].category, "extensions")
        XCTAssertEqual(r1[1].level, .error)
        XCTAssertEqual(r1[1].message, "Test error 123")
    }

    func testRemoveAllSinksStopsBroadcasting() {
        let sink = TestLogSink()
        Log.addSink(sink)
        Log.settings.info("Before clear")
        XCTAssertEqual(sink.getRecords().count, 1)

        Log.removeAllSinks()
        Log.settings.info("After clear")
        XCTAssertEqual(sink.getRecords().count, 1)
    }

    func testLogPrivateInterpolationRedaction() {
        let sink = TestLogSink()
        Log.addSink(sink)

        let secret = "super-secret-token"
        let unannotated = "unannotated-text"
        let autoVal = "auto-text"
        let publicVal = 42
        Log.settings.info("Auth info: secret=\(secret, privacy: .private) unannotated=\(unannotated) auto=\(autoVal, privacy: .auto) count=\(publicVal, privacy: .public)")

        let records = sink.getRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].message, "Auth info: secret=<private> unannotated=<private> auto=<private> count=42")
    }
}
