import XCTest
@testable import OpenClip

final class DebugLogCommandTests: XCTestCase {
    func testNoArgsIsNone() {
        XCTAssertEqual(DebugLogCommand.parse([]), .none)
        XCTAssertEqual(DebugLogCommand.parse(["OpenClip"]), .none)
    }

    func testNonDoubleDashArgsAreIgnored() {
        // Launcher/framework-owned args (e.g. XCTest's -NSTreatUnknownArgumentsAsOpen)
        // must not abort a normal launch.
        XCTAssertEqual(
            DebugLogCommand.parse(["OpenClip", "-NSTreatUnknownArgumentsAsOpen", "NO"]),
            .none
        )
    }

    func testNegativeCountIsUsageError() {
        guard case .usageError = DebugLogCommand.parse(["OpenClip", "--dump-logs", "--count=-5"]) else {
            return XCTFail("expected usageError")
        }
    }

    func testNonNumericCollectIsUsageError() {
        guard case .usageError = DebugLogCommand.parse(["OpenClip", "--dump-logs", "--collect=abc"]) else {
            return XCTFail("expected usageError")
        }
    }

    func testBareDumpDefaults() {
        guard case .dumpLogs(let opts) = DebugLogCommand.parse(["OpenClip", "--dump-logs"]) else {
            return XCTFail("expected dumpLogs")
        }
        XCTAssertNil(opts.category)
        XCTAssertNil(opts.level)
        XCTAssertEqual(opts.count, 500)
        XCTAssertEqual(opts.collectSeconds, 4)
    }

    func testDumpWithOptions() {
        guard case .dumpLogs(let opts) = DebugLogCommand.parse([
            "OpenClip", "--dump-logs",
            "--category=extensions", "--level=error", "--count=20", "--collect=3"
        ]) else {
            return XCTFail("expected dumpLogs")
        }
        XCTAssertEqual(opts.category, "extensions")
        XCTAssertEqual(opts.level, .error)
        XCTAssertEqual(opts.count, 20)
        XCTAssertEqual(opts.collectSeconds, 3)
    }

    func testHelp() {
        XCTAssertEqual(DebugLogCommand.parse(["OpenClip", "--help"]), .showHelp)
    }

    func testUnknownFlagIsUsageError() {
        guard case .usageError(let message) = DebugLogCommand.parse(["OpenClip", "--bogus"]) else {
            return XCTFail("expected usageError")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testBadLevelIsUsageError() {
        guard case .usageError = DebugLogCommand.parse(["OpenClip", "--dump-logs", "--level=nope"]) else {
            return XCTFail("expected usageError")
        }
    }

    func testFormattedLine() {
        let entry = DebugLogEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            category: "extensions",
            level: .error,
            message: "Extension manifest rejected at /tmp/x"
        )
        let line = DebugLogCommand.formattedLine(entry)
        XCTAssertTrue(line.contains("error"))
        XCTAssertTrue(line.contains("extensions"))
        XCTAssertTrue(line.contains("Extension manifest rejected at /tmp/x"))
    }

    func testUsageIsNonEmpty() {
        XCTAssertFalse(DebugLogCommand.usage.isEmpty)
    }
}