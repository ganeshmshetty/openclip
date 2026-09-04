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

/// Horizontal alignment of the popup bar relative to the cursor ("left" | "center" | "right").
public enum PopupBarAlignment: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
}

/// Vertical placement mode of the popup bar relative to the cursor/selection ("auto" | "above" | "below").
public enum PopupVerticalPosition: String, Codable, CaseIterable, Sendable {
    case auto
    case above
    case below
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

public extension SettingKey where Value == [String: String] {
    /// packageID -> "seen" | "trusted" | "revoked"
    static var extensionTrust: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trust", defaultValue: [:]) }
    /// packageID -> content hash recorded at enable time (tamper-watch baseline)
    static var extensionTrustHashes: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trustHashes", defaultValue: [:]) }
    /// packageID -> "store" | "local"
    static var extensionSources: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.sources", defaultValue: [:]) }
}

public extension SettingKey where Value == Bool {
    static var isAppEnabled: SettingKey<Bool> { SettingKey<Bool>("isAppEnabled", defaultValue: true) }
    static var isAIEnabled: SettingKey<Bool> { SettingKey<Bool>("aiEnabled", defaultValue: true) }
    static var isMouseHoldEnabled: SettingKey<Bool> { SettingKey<Bool>("isMouseHoldEnabled", defaultValue: true) }
    static var hasCompletedOnboarding: SettingKey<Bool> { SettingKey<Bool>("hasCompletedOnboarding", defaultValue: false) }
    /// True once the one-time post-onboarding coach-mark ("select any text" / "finish setup")
    /// has been dismissed by any path — it never shows again for this install.
    static var hasDismissedPostOnboardingCoachMark: SettingKey<Bool> { SettingKey<Bool>("hasDismissedPostOnboardingCoachMark", defaultValue: false) }
    static var startAtLogin: SettingKey<Bool> { SettingKey<Bool>("startAtLogin", defaultValue: false) }
    static var completionCopyToClipboard: SettingKey<Bool> { SettingKey<Bool>("completionCopyToClipboard", defaultValue: false) }
    /// True once the one-time migration (auto-trust existing installs) has run.
    static var extensionTrustMigrated: SettingKey<Bool> { SettingKey<Bool>("extension.trustMigrated", defaultValue: false) }
    static var automaticallyChecksForUpdates: SettingKey<Bool> { SettingKey<Bool>("automaticallyChecksForUpdates", defaultValue: true) }
    static var automaticallyDownloadsUpdates: SettingKey<Bool> { SettingKey<Bool>("automaticallyDownloadsUpdates", defaultValue: true) }
    static var notifyOnUpdate: SettingKey<Bool> { SettingKey<Bool>("notifyOnUpdate", defaultValue: true) }
}

public extension SettingKey where Value == Int {
    /// Number of actions displayed per page in the popup bar (legacy, default 7).
    static var popupPageSize: SettingKey<Int> { SettingKey<Int>("popupPageSize", defaultValue: 7) }
    /// Maximum width budget level for the popup bar from 1 to 5 (3 = Standard / Default ~540pt).
    static var popupBarWidth: SettingKey<Int> { SettingKey<Int>("popupBarWidth", defaultValue: 3) }
    /// Visual scaling level for the popup from 1 to 5 (3 = Normal / Default).
    static var popupScale: SettingKey<Int> { SettingKey<Int>("popupScale", defaultValue: 3) }
}

public extension SettingKey where Value == Double {
    /// Duration in seconds the mouse must be held down to trigger the popup (0.0 = disabled).
    static var mouseHoldDuration: SettingKey<Double> { SettingKey<Double>("mouseHoldDuration", defaultValue: 0.3) }
    /// Timestamp (seconds since 1970) until which OpenClip is temporarily paused (0.0 = not paused).
    static var pauseUntilTimestamp: SettingKey<Double> { SettingKey<Double>("pauseUntilTimestamp", defaultValue: 0.0) }
}

public extension SettingKey where Value == Data? {
    static var actionCustomizations: SettingKey<Data?> { SettingKey<Data?>("action.customizations", defaultValue: nil) }
    static var actionGroups: SettingKey<Data?> { SettingKey<Data?>("action.groups", defaultValue: nil) }
}

public extension SettingKey where Value == String {
    static var calendarProvider: SettingKey<String> { SettingKey<String>("action.calendar.provider", defaultValue: "native") }
    static var searchURL: SettingKey<String> { SettingKey<String>("action.search.url", defaultValue: "https://www.google.com/search?q={query}") }

    /// The user's chosen behavior when an action returns text (General tab →
    /// "Action Results"): "preview" | "paste" | "copy". The raw `ResultDeliveryPreference`
    /// values; defaults preserve today's behavior (primary pastes, secondary copies).
    static var primaryClickBehavior: SettingKey<String> { SettingKey<String>("resultDelivery.primary", defaultValue: "paste") }
    static var secondaryClickBehavior: SettingKey<String> { SettingKey<String>("resultDelivery.secondary", defaultValue: "copy") }

    /// Popup theme ("classic"/"glass") and shared appearance ("system"/"light"/"dark").
    static var popupTheme: SettingKey<String> { SettingKey<String>("popupTheme", defaultValue: "classic") }
    static var popupThemeColor: SettingKey<String> { SettingKey<String>("popupThemeColor", defaultValue: "system") }
    /// Popup horizontal alignment relative to cursor ("left" | "center" | "right").
    static var popupAlignment: SettingKey<String> { SettingKey<String>("popupAlignment", defaultValue: PopupBarAlignment.left.rawValue) }
    /// Popup vertical placement relative to cursor/selection ("auto" | "above" | "below").
    static var popupVerticalPosition: SettingKey<String> { SettingKey<String>("popupVerticalPosition", defaultValue: PopupVerticalPosition.auto.rawValue) }

    /// The last version string (CFBundleShortVersionString) the app was launched on.
    /// Used to classify launch scenarios (First Install, App Update, Reinstall, Normal Launch).
    static var lastRunVersion: SettingKey<String> { SettingKey<String>("app.lastRunVersion", defaultValue: "") }
    /// The last build number (CFBundleVersion) the app was launched on.
    static var lastRunBuild: SettingKey<String> { SettingKey<String>("app.lastRunBuild", defaultValue: "") }

    /// Per-action option value key. The key name matches the legacy `action.<id>.option.<optID>`
    /// convention so existing stored values migrate over with zero data changes.
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey<String>("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}

