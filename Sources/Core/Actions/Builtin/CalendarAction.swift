// CalendarAction.swift
// OpenClip
//
// Implements the builtin calendar action for creating events from selected text using configurable calendar providers.
import Foundation

public struct CalendarAction: ConfigurableAction {
    public let id = "builtin.calendar"
    public let title = "Add Event"
    public let icon = ActionIcon.symbol("calendar.badge.plus")
    public let preferenceIconName = "calendar.badge.plus"

    public var actionOptions: [ExtensionOption] {
        [
            ExtensionOption(
                identifier: "provider",
                label: "Calendar Destination",
                type: .multiple,
                defaultValue: "native",
                options: ["native", "google"]
            )
        ]
    }

    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 300 else { return false }
        return detectDate(in: text) != nil
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = detectDate(in: text) else {
            return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
        }
        
        let provider = settingsStore.get(.calendarProvider)
        if provider == "google" {
            return .openURL(makeGoogleCalendarURL(title: text, startDate: date))
        } else {
            if let icsURL = makeNativeCalendarICSURL(title: text, startDate: date) {
                return .openURL(icsURL)
            }
            return .openURL(makeGoogleCalendarURL(title: text, startDate: date))
        }
    }

    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private func detectDate(in text: String) -> Date? {
        let matches = Self.dateDetector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        return matches?.first?.date
    }

    private func makeNativeCalendarICSURL(title: String, startDate: Date) -> URL? {
        let endDate = startDate.addingTimeInterval(3600)
        let startStr = formatDateForGCal(startDate)
        let endStr = formatDateForGCal(endDate)

        let cleanTitle = title.replacingOccurrences(of: "\n", with: " ")
        let icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//OpenClip//NONSGML Event//EN
        BEGIN:VEVENT
        SUMMARY:\(cleanTitle)
        DTSTART:\(startStr)
        DTEND:\(endStr)
        END:VEVENT
        END:VCALENDAR
        """

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("OpenClipEvent.ics")
        do {
            try icsContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Log.resultHandler.error("Failed to write .ics calendar event: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeGoogleCalendarURL(title: String, startDate: Date) -> URL {
        let startStr = formatDateForGCal(startDate)
        let endDate = startDate.addingTimeInterval(3600)
        let endStr = formatDateForGCal(endDate)

        var components = URLComponents(string: "https://calendar.google.com/calendar/render")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: title),
            URLQueryItem(name: "dates", value: "\(startStr)/\(endStr)")
        ]
        return components.url ?? URL(string: "https://calendar.google.com")!
    }

    private func formatDateForGCal(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return df.string(from: date)
    }
}
