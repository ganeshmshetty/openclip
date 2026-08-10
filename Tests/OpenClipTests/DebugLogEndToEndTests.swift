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

        let deadline = Date().addingTimeInterval(8)
        var found = false
        while Date() < deadline && !found {
            Thread.sleep(forTimeInterval: 0.5)
            found = store.snapshot().contains { $0.message.contains(marker) }
        }
        XCTAssertTrue(found, "store should capture the E2E marker line within 8s")
    }
}