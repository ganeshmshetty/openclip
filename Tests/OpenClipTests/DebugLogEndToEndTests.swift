import Core
import XCTest
@testable import OpenClip

/// Exercises the full store path deterministically inside the test runner's own process:
/// write a real line through `Log`, let the poller read it back via OSLogStore, and assert
/// the marker appears in the buffer. No `~/.openclip` or app-singleton dependency.
final class DebugLogEndToEndTests: XCTestCase {
    func testStoreCapturesRealLogLine() {
        let marker = "E2E_MARKER_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let store = DebugLogStore(
            reader: UnifiedLogReader(),
            buffer: DebugLogBuffer(capacity: 500),
            pollInterval: 0.5
        )
        store.start()
        defer { store.stop() }

        Log.extensions.error("\(marker, privacy: .public) e2e probe")

        let deadline = Date().addingTimeInterval(15)
        var found = false
        while Date() < deadline && !found {
            Thread.sleep(forTimeInterval: 0.5)
            found = store.snapshot().contains { $0.message.contains(marker) }
        }
        XCTAssertTrue(found, "store should capture the E2E marker line within 15s")
    }

    /// `limit <= 0` must short-circuit to an empty result BEFORE the store is read — with real
    /// entries present, the current (unpatched) loop would append one entry and break at
    /// `result.count >= limit`, returning 1 entry instead of 0.
    func testReadWithNonPositiveLimitReturnsNoEntries() throws {
        let marker = "E2E_LZ_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let reader = UnifiedLogReader()
        Log.extensions.error("\(marker, privacy: .public) limit-zero probe")

        // Wait until the marker is actually readable via a positive limit, so the empty assertion
        // below is meaningful (a trivially-empty store would false-pass).
        let deadline = Date().addingTimeInterval(15)
        var readable = false
        while Date() < deadline && !readable {
            Thread.sleep(forTimeInterval: 0.5)
            let entries = try reader.read(after: nil, limit: 100)
            readable = entries.contains { $0.message.contains(marker) }
        }
        XCTAssertTrue(readable, "probe line should be readable with a positive limit within 15s")

        XCTAssertTrue(try reader.read(after: nil, limit: 0).isEmpty,
                      "limit 0 must return no entries even when entries exist")
        XCTAssertTrue(try reader.read(after: nil, limit: -1).isEmpty,
                      "negative limit must return no entries even when entries exist")
    }
}
