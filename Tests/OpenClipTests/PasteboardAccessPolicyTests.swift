import AppKit
import os
import XCTest
@testable import Core
@testable import OpenClip

final class PasteboardAccessPolicyTests: XCTestCase {
    func testOnlyAlwaysDenyBlocksReads() {
        XCTAssertTrue(PasteboardAccessPolicy(read: { .denied }).deniesReads)
        XCTAssertFalse(PasteboardAccessPolicy(read: { .allowed }).deniesReads)
        XCTAssertFalse(PasteboardAccessPolicy(read: { .asks }).deniesReads)
        XCTAssertFalse(PasteboardAccessPolicy(read: { .unknown }).deniesReads)
    }
}

@MainActor
final class HotkeyPasteboardDenialTests: XCTestCase {
    private final class SelectionLogSink: LogSink, @unchecked Sendable {
        let messages = OSAllocatedUnfairLock<[String]>(initialState: [])
        func record(date: Date, category: String, level: Core.LogLevel, message: String) {
            guard category == "selection" else { return }
            messages.withLock { $0.append(message) }
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            HotkeyManager.shared.selectionMonitor = nil
            HotkeyManager.shared.pasteboardAccess = PasteboardAccessPolicy()
            HotkeyManager.shared.didLogPasteboardDenied = false
        }
    }

    override func tearDown() async throws {
        HotkeyManager.shared.pasteboardAccess = PasteboardAccessPolicy()
        HotkeyManager.shared.didLogPasteboardDenied = false
        try await super.tearDown()
    }

    func testDeniedPasteboardReadBehavesLikeEmptyClipboardAndLogsOnce() throws {
        let manager = HotkeyManager.shared
        manager.pasteboardAccess = PasteboardAccessPolicy(read: { .denied })
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(board)
        defer { snapshot.restore(to: board) }
        board.clearContents()
        board.setString("clipboard text that must stay unread", forType: .string)

        let sink = SelectionLogSink()
        let previous = Log.currentSinks()
        Log.addSink(sink)
        defer { Log.restoreSinks(previous) }

        let app = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let first = try XCTUnwrap(manager.resolveSynchronousTrigger(frontmostApp: app))
        let second = try XCTUnwrap(manager.resolveSynchronousTrigger(frontmostApp: app))

        XCTAssertEqual(first.context.text, "")
        XCTAssertFalse(first.context.isClipboardFallback)
        XCTAssertEqual(second.context.text, "")

        let denialLogs = sink.messages.withLock { messages in
            messages.filter { $0.contains("system pasteboard access policy") }
        }
        XCTAssertEqual(denialLogs.count, 1, "A denied read must be reported once, not on every hotkey press")
    }

    func testAllowedPasteboardStillReadsClipboardText() throws {
        let manager = HotkeyManager.shared
        manager.pasteboardAccess = PasteboardAccessPolicy(read: { .allowed })
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(board)
        defer { snapshot.restore(to: board) }
        board.clearContents()
        board.setString("allowed clipboard text", forType: .string)

        let trigger = try XCTUnwrap(
            manager.resolveSynchronousTrigger(frontmostApp: MockFrontmostApp(bundleID: "com.apple.TextEdit"))
        )
        XCTAssertEqual(trigger.context.text, "allowed clipboard text")
        XCTAssertTrue(trigger.context.isClipboardFallback)
    }
}

private final class MockFrontmostApp: NSRunningApplication {
    private let bundleID: String?

    init(bundleID: String?) {
        self.bundleID = bundleID
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var processIdentifier: pid_t { 1001 }
}
