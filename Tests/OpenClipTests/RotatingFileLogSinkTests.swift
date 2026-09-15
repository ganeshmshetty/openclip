import XCTest
@testable import Core
@testable import OpenClip

final class RotatingFileLogSinkTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClipLogTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    @MainActor
    func testLogSinkCreatesFileAndWritesEntries() throws {
        let sink = RotatingFileLogSink(
            logDirectory: tempDirectory,
            fileName: "test.log",
            maxFileSize: 1024 * 1024,
            maxBackups: 2
        )

        let date = Date(timeIntervalSince1970: 1700000000)
        sink.record(date: date, category: "extensions", level: .notice, message: "Loaded extension foo")
        sink.flush()

        let logFile = tempDirectory.appendingPathComponent("test.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)

        let content = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(content.contains("notice extensions Loaded extension foo"))
    }

    @MainActor
    func testLogSinkRotatesWhenSizeExceedsCap() throws {
        // Use a small cap (120 bytes) to force rotation with few lines
        let sink = RotatingFileLogSink(
            logDirectory: tempDirectory,
            fileName: "test.log",
            maxFileSize: 120,
            maxBackups: 2
        )

        for i in 1...10 {
            sink.record(
                date: Date(timeIntervalSince1970: Double(1700000000 + i)),
                category: "cat",
                level: .info,
                message: "Message number \(i) with padding to fill up the file"
            )
        }
        sink.flush()

        let currentLog = tempDirectory.appendingPathComponent("test.log")
        let backup1 = tempDirectory.appendingPathComponent("test.1.log")
        let backup2 = tempDirectory.appendingPathComponent("test.2.log")
        let backup3 = tempDirectory.appendingPathComponent("test.3.log")

        XCTAssertTrue(FileManager.default.fileExists(atPath: currentLog.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup2.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup3.path), "Max backups is 2, so .3 should not exist")
    }

    @MainActor
    func testConcurrentWritesAreThreadSafe() throws {
        let sink = RotatingFileLogSink(
            logDirectory: tempDirectory,
            fileName: "concurrent.log",
            maxFileSize: 1024 * 1024,
            maxBackups: 2
        )

        let iterations = 100
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            sink.record(date: Date(), category: "thread", level: .debug, message: "Concurrent write \(i)")
        }
        sink.flush()

        let logFile = tempDirectory.appendingPathComponent("concurrent.log")
        let content = try String(contentsOf: logFile, encoding: .utf8)
        let lineCount = content.split(separator: "\n").count
        XCTAssertEqual(lineCount, iterations)
    }

    @MainActor
    func testConcurrentRecordsKeepEachTimestampWithItsMessage() throws {
        let sink = RotatingFileLogSink(
            logDirectory: tempDirectory,
            fileName: "timestamps.log",
            maxFileSize: 1024 * 1024,
            maxBackups: 2
        )
        // Same configuration as the sink. The expected strings then use the same local time zone.
        let expectedFormatter = DateFormatter()
        expectedFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        expectedFormatter.locale = Locale(identifier: "en_US_POSIX")

        let iterations = 1000
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000.123)
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            sink.record(
                date: baseDate.addingTimeInterval(Double(i)),
                category: "thread",
                level: .debug,
                message: "write \(i)"
            )
        }
        sink.flush()

        let content = try String(
            contentsOf: tempDirectory.appendingPathComponent("timestamps.log"),
            encoding: .utf8
        )
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, iterations)

        var seen = Set<Int>()
        for line in lines {
            guard let marker = line.range(of: " debug thread write "),
                  let i = Int(line[marker.upperBound...]) else {
                XCTFail("Malformed line: \(line)")
                continue
            }
            XCTAssertEqual(
                String(line[..<marker.lowerBound]),
                expectedFormatter.string(from: baseDate.addingTimeInterval(Double(i)))
            )
            seen.insert(i)
        }
        XCTAssertEqual(seen.count, iterations)
    }
}
