import XCTest
@testable import Core
@testable import OpenClip

private func makeEntry(_ n: Int) -> DebugLogEntry {
    DebugLogEntry(id: 0, date: Date(timeIntervalSince1970: Double(n)), category: "test", level: .info, message: "m\(n)")
}

final class DebugLogBufferTests: XCTestCase {
    func testAppendsStayChronological() {
        let buffer = DebugLogBuffer(capacity: 10)
        buffer.append(makeEntry(1))
        buffer.append(makeEntry(2))
        buffer.append(makeEntry(3))
        XCTAssertEqual(buffer.snapshot().map(\.message), ["m1", "m2", "m3"])
    }

    func testCapacityEvictsOldest() {
        let buffer = DebugLogBuffer(capacity: 3)
        for n in 1...5 { buffer.append(makeEntry(n)) }
        XCTAssertEqual(buffer.snapshot().map(\.message), ["m3", "m4", "m5"])
        XCTAssertEqual(buffer.count, 3)
    }

    func testAppendAssignsStableSequentialIDs() {
        let buffer = DebugLogBuffer(capacity: 10)
        buffer.append(makeEntry(1))
        buffer.append(makeEntry(2))
        buffer.append(makeEntry(3))
        XCTAssertEqual(buffer.snapshot().map(\.id), [0, 1, 2])
    }

    func testClearEmpties() {
        let buffer = DebugLogBuffer(capacity: 10)
        buffer.append(makeEntry(1))
        buffer.clear()
        XCTAssertTrue(buffer.snapshot().isEmpty)
    }

    func testAppendContentsOf() {
        let buffer = DebugLogBuffer(capacity: 10)
        let batch = [DebugLogEntry(date: .distantPast, category: "t", level: .debug, message: "a"),
                     DebugLogEntry(date: .distantPast, category: "t", level: .debug, message: "b")]
        buffer.append(contentsOf: batch)
        XCTAssertEqual(buffer.snapshot().map(\.message), ["a", "b"])
    }

    func testConcurrentAppendsAreSafe() {
        let buffer = DebugLogBuffer(capacity: 10_000)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "concurrent.buffer.test", attributes: .concurrent)
        for t in 0..<8 {
            queue.async(group: group) {
                for n in 0..<100 { buffer.append(makeEntry(t * 100 + n)) }
            }
        }
        group.wait()
        XCTAssertEqual(buffer.count, 800)
    }
}
