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

/// Stable per-action option namespaces (Phase 7). `defaultsKey` is the SettingsStore/UserDefaults
/// key for non-secret options; `keychainAccount` names the Keychain account for `.secret` options.
/// Both produce the same `action.<actionID>.option.<optionID>` string — one namespace, two backends
/// (secrets never touch UserDefaults).
public enum ActionOptionKey {
    public static func defaultsKey(actionID: String, optionID: String) -> String {
        "action.\(actionID).option.\(optionID)"
    }

    public static func keychainAccount(actionID: String, optionID: String) -> String {
        defaultsKey(actionID: actionID, optionID: optionID)
    }
}

public extension SettingKey where Value == [String] {
    static var actionOrder: SettingKey<[String]> { SettingKey<[String]>("action.order", defaultValue: []) }
}

public extension SettingKey where Value == Set<String> {
    static var disabledActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledActionIDs", defaultValue: []) }
    static var disabledPackages: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledPackages", defaultValue: []) }
}

public extension SettingKey where Value == [String: Int] {
    static var actionUsageRecency: SettingKey<[String: Int]> { SettingKey<[String: Int]>("actionUsageRecency", defaultValue: [:]) }
}

public extension SettingKey where Value == Bool {
    static var isAppEnabled: SettingKey<Bool> { SettingKey<Bool>("isAppEnabled", defaultValue: true) }
    static var hasCompletedOnboarding: SettingKey<Bool> { SettingKey<Bool>("hasCompletedOnboarding", defaultValue: false) }
    static var startAtLogin: SettingKey<Bool> { SettingKey<Bool>("startAtLogin", defaultValue: false) }
    static var completionCopyToClipboard: SettingKey<Bool> { SettingKey<Bool>("completionCopyToClipboard", defaultValue: false) }
}

public extension SettingKey where Value == Double {
    /// Visual scaling factor for the popup (1.0 = 100%).
    static var popupScale: SettingKey<Double> { SettingKey<Double>("popupScale", defaultValue: 1.0) }
}

public extension SettingKey where Value == Data? {
    static var actionCustomizations: SettingKey<Data?> { SettingKey<Data?>("action.customizations", defaultValue: nil) }
}

public extension SettingKey where Value == String {
    static var calculateMode: SettingKey<String> { SettingKey<String>("action.calculate.mode", defaultValue: "paste") }
    static var calendarProvider: SettingKey<String> { SettingKey<String>("action.calendar.provider", defaultValue: "native") }
    static var searchURL: SettingKey<String> { SettingKey<String>("action.search.url", defaultValue: "https://www.google.com/search?q={query}") }

    /// Popup theme ("classic"/"glass") and shared appearance ("system"/"light"/"dark").
    static var popupTheme: SettingKey<String> { SettingKey<String>("popupTheme", defaultValue: "classic") }
    static var popupThemeColor: SettingKey<String> { SettingKey<String>("popupThemeColor", defaultValue: "system") }

    /// Per-action option value key. The key name matches the legacy `action.<id>.option.<optID>`
    /// convention so existing stored values migrate over with zero data changes.
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey<String>("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}

