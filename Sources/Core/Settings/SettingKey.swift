// SettingKey.swift
// OpenClip
//
// Defines strongly-typed setting keys and default values for central configuration management via the Settings Door.
import Foundation

public struct SettingKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public extension SettingKey where Value == [String] {
    static var actionOrder: SettingKey<[String]> { SettingKey<[String]>("action.order", defaultValue: []) }
}

public extension SettingKey where Value == Set<String> {
    static var disabledActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledActionIDs", defaultValue: []) }
}

public extension SettingKey where Value == Bool {
    static var isTransformGroupEnabled: SettingKey<Bool> { SettingKey<Bool>("action.transform.enabled", defaultValue: true) }
    static var isAppEnabled: SettingKey<Bool> { SettingKey<Bool>("isAppEnabled", defaultValue: true) }
    static var hasCompletedOnboarding: SettingKey<Bool> { SettingKey<Bool>("hasCompletedOnboarding", defaultValue: false) }
    static var startAtLogin: SettingKey<Bool> { SettingKey<Bool>("startAtLogin", defaultValue: false) }
    static var completionCopyToClipboard: SettingKey<Bool> { SettingKey<Bool>("completionCopyToClipboard", defaultValue: false) }
    static var calculateUseText: SettingKey<Bool> { SettingKey<Bool>("action.calculate.useText", defaultValue: false) }
    static var copyUseText: SettingKey<Bool> { SettingKey<Bool>("action.copy.useText", defaultValue: false) }
    static var cutUseText: SettingKey<Bool> { SettingKey<Bool>("action.cut.useText", defaultValue: false) }
    static var defineUseText: SettingKey<Bool> { SettingKey<Bool>("action.define.useText", defaultValue: false) }
    static var pasteUseText: SettingKey<Bool> { SettingKey<Bool>("action.paste.useText", defaultValue: false) }
}

public extension SettingKey where Value == Data? {
    static var actionCustomizations: SettingKey<Data?> { SettingKey<Data?>("action.customizations", defaultValue: nil) }
}

public extension SettingKey where Value == String {
    static var calculateMode: SettingKey<String> { SettingKey<String>("action.calculate.mode", defaultValue: "paste") }
    static var calendarProvider: SettingKey<String> { SettingKey<String>("action.calendar.provider", defaultValue: "native") }
    static var searchURL: SettingKey<String> { SettingKey<String>("action.search.url", defaultValue: "https://www.google.com/search?q={query}") }

    /// Per-action option value key. The key name matches the legacy `action.<id>.option.<optID>`
    /// convention so existing stored values migrate over with zero data changes.
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey<String>("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}

