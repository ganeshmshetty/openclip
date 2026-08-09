import XCTest
@testable import OpenClip

final class DebugLogFilterTests: XCTestCase {
    private func entry(_ n: Int, category: String, level: DebugLogLevel) -> DebugLogEntry {
        DebugLogEntry(id: 0, date: Date(timeIntervalSince1970: Double(n)), category: category, level: level, message: "m\(n)")
    }

    func testEmptyFilterPassesAllEntriesNewestFirst() {
        let entries = [entry(1, category: "a", level: .info), entry(2, category: "b", level: .error)]
        let out = DebugLogFilter().apply(to: entries)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.message), ["m2", "m1"]) // newest first
    }

    func testFilterByCategory() {
        let entries = [
            entry(1, category: "extensions", level: .info),
            entry(2, category: "ai", level: .info),
            entry(3, category: "extensions", level: .error),
        ]
        let out = DebugLogFilter(category: "extensions").apply(to: entries)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { $0.category == "extensions" })
    }

    func testFilterByLevel() {
        let entries = [
            entry(1, category: "a", level: .info),
            entry(2, category: "b", level: .error),
            entry(3, category: "c", level: .error),
        ]
        let out = DebugLogFilter(level: .error).apply(to: entries)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { $0.level == .error })
    }

    func testNewestFirstOrdering() {
        let entries = [entry(1, category: "a", level: .info),
                       entry(2, category: "a", level: .info),
                       entry(3, category: "a", level: .info)]
        let out = DebugLogFilter().apply(to: entries)
        XCTAssertEqual(out.map(\.message), ["m3", "m2", "m1"])
    }

    func testCountCap() {
        let entries = (1...10).map { entry($0, category: "a", level: .info) }
        let out = DebugLogFilter(count: 3).apply(to: entries)
        XCTAssertEqual(out.map(\.message), ["m10", "m9", "m8"])
    }

    func testCountZeroMeansNoCap() {
        let entries = (1...10).map { entry($0, category: "a", level: .info) }
        let out = DebugLogFilter(count: 0).apply(to: entries)
        XCTAssertEqual(out.count, 10)
    }
}