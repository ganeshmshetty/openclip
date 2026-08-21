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
}
