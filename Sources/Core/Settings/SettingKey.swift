// SettingKey.swift
// OpenClip
//
// Defines strongly-typed setting keys and default values for central configuration management via the Settings Door.
import Foundation

public struct SettingKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    /// Bumped when the stored value's shape changes, so a migration can tell old data from new.
    public let schemaVersion: Int

    public init(_ name: String, defaultValue: Value, schemaVersion: Int = 1) {
        self.name = name
        self.defaultValue = defaultValue
        self.schemaVersion = schemaVersion
    }
}

/// Per-action option namespace: `defaultsKey` and `keychainAccount` yield the same string; secrets never touch UserDefaults.
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

/// Which side of the main bar the contextual actions island sits on ("auto" | "left" | "right").
/// `auto` follows the bar's alignment: right-aligned puts the island on the right, otherwise left.
public enum ContextualPillPosition: String, Codable, CaseIterable, Sendable {
    case auto
    case left
    case right

    /// True when the island should be drawn after (to the right of) the standard island.
    public func isTrailing(for alignment: PopupBarAlignment) -> Bool {
        switch self {
        case .left: return false
        case .right: return true
        case .auto: return alignment == .right
        }
    }
}

/// Vertical placement mode of the popup bar relative to the cursor/selection ("auto" | "above" | "below").
public enum PopupVerticalPosition: String, Codable, CaseIterable, Sendable {
    case auto
    case above
    case below
}

/// Sparkle update feed. Beta uses a separate appcast, so opting in never affects stable users.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta
}

public extension SettingKey where Value == [String] {
    static var actionOrder: SettingKey<[String]> { SettingKey<[String]>("action.order", defaultValue: []) }
}

public extension SettingKey where Value == Set<String> {
    static var standaloneAIActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("standaloneAIActionIDs", defaultValue: []) }
    static var disabledActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledActionIDs", defaultValue: []) }
    static var disabledPackages: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledPackages", defaultValue: []) }
    static var disabledContextualActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledContextualActionIDs", defaultValue: []) }
}

public extension SettingKey where Value == [String: Int] {
    static var actionUsageRecency: SettingKey<[String: Int]> { SettingKey<[String: Int]>("actionUsageRecency", defaultValue: [:]) }
}

public extension SettingKey where Value == [String: [String]] {
    static var extensionGroupMemberOrder: SettingKey<[String: [String]]> { SettingKey<[String: [String]]>("extensionGroupMemberOrder", defaultValue: [:]) }
}

public extension SettingKey where Value == [String: String] {
    /// packageID -> "seen" | "trusted" | "revoked"
    static var extensionTrust: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trust", defaultValue: [:]) }
    /// packageID -> content hash recorded at enable time (tamper-watch baseline)
    static var extensionTrustHashes: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trustHashes", defaultValue: [:]) }
    /// packageID -> "store" | "local"
    static var extensionSources: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.sources", defaultValue: [:]) }
    /// actionID -> lowercase exact-match search alias
    static var actionAliases: SettingKey<[String: String]> { SettingKey<[String: String]>("action.aliases", defaultValue: [:]) }
}

public extension SettingKey where Value == Bool {
    static var showSearchAllActions: SettingKey<Bool> { SettingKey<Bool>("showSearchAllActions", defaultValue: true) }
    static var isAppEnabled: SettingKey<Bool> { SettingKey<Bool>("isAppEnabled", defaultValue: true) }
    static var isAIEnabled: SettingKey<Bool> { SettingKey<Bool>("aiEnabled", defaultValue: true) }
    static var isMouseHoldEnabled: SettingKey<Bool> { SettingKey<Bool>("isMouseHoldEnabled", defaultValue: true) }
    static var hasCompletedOnboarding: SettingKey<Bool> { SettingKey<Bool>("hasCompletedOnboarding", defaultValue: false) }
    /// Once dismissed by any path, the post-onboarding coach-mark never shows again.
    static var hasDismissedPostOnboardingCoachMark: SettingKey<Bool> { SettingKey<Bool>("hasDismissedPostOnboardingCoachMark", defaultValue: false) }
    static var startAtLogin: SettingKey<Bool> { SettingKey<Bool>("startAtLogin", defaultValue: false) }
    /// Plays a short system sound when an action copies to the clipboard.
    static var playCopySound: SettingKey<Bool> { SettingKey<Bool>("playCopySound", defaultValue: false) }
    static var captureTextAutoCopy: SettingKey<Bool> { SettingKey<Bool>("captureTextAutoCopy", defaultValue: true) }
    static var completionCopyToClipboard: SettingKey<Bool> { SettingKey<Bool>("completionCopyToClipboard", defaultValue: false) }
    /// True once the one-time migration (auto-trust existing installs) has run.
    static var extensionTrustMigrated: SettingKey<Bool> { SettingKey<Bool>("extension.trustMigrated", defaultValue: false) }
    static var automaticallyChecksForUpdates: SettingKey<Bool> { SettingKey<Bool>("automaticallyChecksForUpdates", defaultValue: true) }
    static var automaticallyDownloadsUpdates: SettingKey<Bool> { SettingKey<Bool>("automaticallyDownloadsUpdates", defaultValue: false) }
    static var automaticallyUpdatesExtensions: SettingKey<Bool> { SettingKey<Bool>("extension.automaticallyUpdates", defaultValue: true) }
    static var notifyOnUpdate: SettingKey<Bool> { SettingKey<Bool>("notifyOnUpdate", defaultValue: true) }
    static var contextualActionsEnabled: SettingKey<Bool> { SettingKey<Bool>("contextualActionsEnabled", defaultValue: true) }
}

public extension SettingKey where Value == Int {
    /// Target number of actions displayed per page in the popup bar (2...24, default 6).
    static var popupPageSize: SettingKey<Int> { SettingKey<Int>("popupPageSize", defaultValue: 6) }
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
    static var customActions: SettingKey<Data?> { SettingKey<Data?>("customActions", defaultValue: nil) }
}

public extension SettingKey where Value == String {
    /// Which copy sound plays (a `CopySound` raw value); unknown values fall back to the default.
    static var copySoundName: SettingKey<String> { SettingKey<String>("copySoundName", defaultValue: "swoosh") }
    static var lastAppUpdateNotificationIdentifier: SettingKey<String> { SettingKey<String>("lastAppUpdateNotificationIdentifier", defaultValue: "") }
    static var lastAnnouncedAppUpdateVersion: SettingKey<String> { SettingKey<String>("lastAnnouncedAppUpdateVersion", defaultValue: "") }
    /// Which side of the main bar the contextual actions island sits on; see `ContextualPillPosition`.
    static var contextualPillPosition: SettingKey<String> { SettingKey<String>("contextualPillPosition", defaultValue: ContextualPillPosition.auto.rawValue) }
    static var calendarProvider: SettingKey<String> { SettingKey<String>("action.calendar.provider", defaultValue: "native") }
    static var searchURL: SettingKey<String> { SettingKey<String>("action.search.url", defaultValue: "https://www.google.com/search?q={query}") }


    /// Default directory where action file outputs are saved. Defaults to empty string (which resolves to ~/Downloads).
    static var fileSaveLocation: SettingKey<String> { SettingKey<String>("fileSaveLocation", defaultValue: "") }

    /// Popup theme ("classic"/"glass") and shared appearance ("system"/"light"/"dark").
    static var popupTheme: SettingKey<String> { SettingKey<String>("popupTheme", defaultValue: "classic") }
    static var popupThemeColor: SettingKey<String> { SettingKey<String>("popupThemeColor", defaultValue: "system") }
    /// Popup horizontal alignment relative to cursor ("left" | "center" | "right").
    static var popupAlignment: SettingKey<String> { SettingKey<String>("popupAlignment", defaultValue: PopupBarAlignment.left.rawValue) }
    /// Popup vertical placement relative to cursor/selection ("auto" | "above" | "below").
    static var popupVerticalPosition: SettingKey<String> { SettingKey<String>("popupVerticalPosition", defaultValue: PopupVerticalPosition.auto.rawValue) }

    /// Last launched CFBundleShortVersionString; used to classify launch scenarios.
    static var lastRunVersion: SettingKey<String> { SettingKey<String>("app.lastRunVersion", defaultValue: "") }
    /// The last build number (CFBundleVersion) the app was launched on.
    static var lastRunBuild: SettingKey<String> { SettingKey<String>("app.lastRunBuild", defaultValue: "") }

    /// Which update feed the app follows: `UpdateChannel.stable` (default) or `UpdateChannel.beta`.
    static var updateChannel: SettingKey<String> { SettingKey<String>("updates.channel", defaultValue: UpdateChannel.stable.rawValue) }

    /// Matches the legacy `action.<id>.option.<optID>` key so stored values migrate unchanged.
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey<String>("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}
