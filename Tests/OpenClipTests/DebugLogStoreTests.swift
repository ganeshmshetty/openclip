import XCTest
@testable import Core
@testable import OpenClip

private func makeEntry(_ n: Int, level: LogLevel = .notice) -> DebugLogEntry {
    DebugLogEntry(id: 0, date: Date(timeIntervalSince1970: Double(n)), category: "test", level: level, message: "m\(n)")
}

final class DebugLogStoreTests: XCTestCase {
    func testStoreCapturesEntriesViaBuffer() {
        let buffer = DebugLogBuffer(capacity: 100)
        let store = DebugLogStore(buffer: buffer)

        buffer.record(date: Date(timeIntervalSince1970: 1), category: "test", level: .notice, message: "m1")
        buffer.record(date: Date(timeIntervalSince1970: 2), category: "test", level: .notice, message: "m2")

        XCTAssertEqual(store.snapshot().map(\.message), ["m1", "m2"])
    }

    func testEntriesMatchingAppliesFilter() {
        let buffer = DebugLogBuffer(capacity: 100)
        let store = DebugLogStore(buffer: buffer)

        buffer.record(date: Date(timeIntervalSince1970: 1), category: "cat1", level: .notice, message: "m1")
        buffer.record(date: Date(timeIntervalSince1970: 2), category: "cat2", level: .error, message: "m2")

        let errorOnly = store.entries(matching: DebugLogFilter(level: .error))
        XCTAssertEqual(errorOnly.map(\.message), ["m2"])

        let cat1Only = store.entries(matching: DebugLogFilter(category: "cat1"))
        XCTAssertEqual(cat1Only.map(\.message), ["m1"])
    }

    func testClearEmptiesBuffer() {
        let buffer = DebugLogBuffer(capacity: 100)
        let store = DebugLogStore(buffer: buffer)

        buffer.record(date: Date(timeIntervalSince1970: 1), category: "test", level: .notice, message: "m1")
        XCTAssertEqual(store.snapshot().count, 1)

        store.clear()
        XCTAssertEqual(store.snapshot().count, 0)
    }
}
