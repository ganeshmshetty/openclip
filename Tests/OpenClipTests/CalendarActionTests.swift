// CalendarActionTests.swift
// OpenClip
//
// Tests for CalendarAction destination providers and options.
import XCTest
import Core
@testable import OpenClip

@MainActor
final class CalendarActionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    func testIsEnabledWithValidDate() {
        let action = CalendarAction()
        let context = ActionContext(
            selection: SelectionContext(
                text: "Meeting with Sarah tomorrow at 3pm",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )
        XCTAssertTrue(action.isEnabled(for: context))
    }

    func testIsEnabledWithNoDate() {
        let action = CalendarAction()
        let context = ActionContext(
            selection: SelectionContext(
                text: "Just some ordinary text with no date",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )
        XCTAssertFalse(action.isEnabled(for: context))
    }

    func testPerformNativeGeneratesICS() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.calendar", optionID: "provider"), value: "native")
        let action = CalendarAction(settingsStore: store)
        let context = ActionContext(
            selection: SelectionContext(
                text: "Dentist appointment tomorrow at 10am",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )

        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertTrue(url.isFileURL)
            XCTAssertTrue(url.pathExtension == "ics")
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(content.contains("BEGIN:VCALENDAR"))
            XCTAssertTrue(content.contains("BEGIN:VEVENT"))
        } else {
            XCTFail("Expected .openURL with .ics file URL, got \(result)")
        }
    }

    func testPerformBusyCalOpensBusyCalURL() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.calendar", optionID: "provider"), value: "busycal")
        let action = CalendarAction(settingsStore: store)
        let context = ActionContext(
            selection: SelectionContext(
                text: "Coffee with Mark on Friday at 4pm",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )

        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.scheme, "busycalevent")
            XCTAssertTrue(url.absoluteString.starts(with: "busycalevent://new/"))
        } else {
            XCTFail("Expected .openURL with busycalevent scheme, got \(result)")
        }
    }

    func testPerformFantasticalOpensFantasticalURL() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.calendar", optionID: "provider"), value: "fantastical")
        let action = CalendarAction(settingsStore: store)
        let context = ActionContext(
            selection: SelectionContext(
                text: "Lunch next Monday at 1pm",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )

        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.scheme, "x-fantastical3")
            XCTAssertTrue(url.absoluteString.contains("sentence="))
        } else {
            XCTFail("Expected .openURL with x-fantastical3 scheme, got \(result)")
        }
    }

    func testPerformGoogleOpensGoogleCalendarURL() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.calendar", optionID: "provider"), value: "google")
        let action = CalendarAction(settingsStore: store)
        let context = ActionContext(
            selection: SelectionContext(
                text: "Team sync tomorrow at 11am",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )

        let result = try await action.perform(context)
        if case .openURL(let url) = result {
            XCTAssertEqual(url.host, "calendar.google.com")
            XCTAssertTrue(url.absoluteString.contains("action=TEMPLATE"))
        } else {
            XCTFail("Expected .openURL with Google Calendar URL, got \(result)")
        }
    }

    // MARK: - Temporary .ics cleanup

    func testHandlerCleansUpICSFileAfterDelay() async throws {
        // Generate a real .ics through the native provider (same path the bug report used).
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: "builtin.calendar", optionID: "provider"), value: "native")
        let action = CalendarAction(settingsStore: store)
        let context = ActionContext(
            selection: SelectionContext(
                text: "Dentist appointment tomorrow at 10am",
                sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes"),
                cursorPosition: .zero,
                timestamp: Date(),
                appPolicy: .default
            )
        )
        let result = try await action.perform(context)
        guard case .openURL(let icsURL) = result, icsURL.isFileURL else {
            return XCTFail("Expected .openURL with an .ics file URL, got \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: icsURL.path), "temp .ics should exist right after generation")
        defer { try? FileManager.default.removeItem(at: icsURL) }

        // Stub the URL open so no real Calendar app is launched; use a short cleanup delay.
        let recorder = OpenedURLRecorder()
        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(),
            pasteboard: NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)")),
            icsCleanupDelay: 0.05,
            openURL: { recorder.record($0) }
        )
        try await handler.handle(.openURL(icsURL), in: nil)
        XCTAssertEqual(recorder.urls, [icsURL], "handler must hand the .ics URL to the injected opener")

        // Still present immediately after handling (cleanup is deferred), gone after the delay.
        XCTAssertTrue(FileManager.default.fileExists(atPath: icsURL.path), "temp .ics must survive until the deferred cleanup runs")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: icsURL.path), "temp .ics should be removed after the cleanup delay")
    }

    func testHandlerDoesNotDeleteNonCalendarICSFile() async throws {
        // An .ics in the temp dir that isn't ours (wrong prefix) must be left alone.
        let otherURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Other-\(UUID().uuidString).ics")
        try Data("BEGIN:VCALENDAR".utf8).write(to: otherURL)
        defer { try? FileManager.default.removeItem(at: otherURL) }

        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(),
            pasteboard: NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)")),
            icsCleanupDelay: 0.05,
            openURL: { _ in }
        )
        try await handler.handle(.openURL(otherURL), in: nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path), "non-calendar .ics must not be deleted")
    }

    func testHandlerDoesNotDeleteICSFileOutsideTemporaryDirectory() async throws {
        // An `OpenClipEvent-*.ics` that isn't in the temp directory (e.g. a URL action pointing at a
        // user file) must not be treated as a generated temp event.
        let scratchDir = URL(fileURLWithPath: "/tmp/OpenClipTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }
        let outsideURL = scratchDir
            .appendingPathComponent("\(Constants.icsFilenamePrefix)\(UUID().uuidString).ics")
        try Data("BEGIN:VCALENDAR".utf8).write(to: outsideURL)

        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(),
            pasteboard: NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)")),
            icsCleanupDelay: 0.05,
            openURL: { _ in }
        )
        try await handler.handle(.openURL(outsideURL), in: nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path), ".ics outside the temp directory must not be deleted")
    }

    func testPurgeStaleCalendarTempFilesRemovesOrphans() throws {
        let stale = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.icsFilenamePrefix)\(UUID().uuidString).ics")
        try Data("BEGIN:VCALENDAR".utf8).write(to: stale)
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("Other-\(UUID().uuidString).ics")
        try Data("BEGIN:VCALENDAR".utf8).write(to: keep)
        defer {
            try? FileManager.default.removeItem(at: stale)
            try? FileManager.default.removeItem(at: keep)
        }

        DefaultActionResultHandler.purgeStaleCalendarTempFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "stale OpenClipEvent .ics must be purged at launch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path), "unrelated .ics must be preserved by the launch purge")
    }
}

/// Thread-safe recorder for the injected `openURL` seam, so tests can assert which URLs the handler
/// handed off without launching a real app.
private final class OpenedURLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []
    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedURLs
    }
    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        storedURLs.append(url)
    }
}
