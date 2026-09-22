// IntegrationSettings.swift
// OpenClip
//
// What the inbound integration is allowed to see and change, and the side effects a raw store
// write cannot perform. The allow-list is deliberately short and presentational: power and
// appearance. Secrets (the AI API key), the extension store, update channel, and hotkeys are not
// reachable over the URL scheme.
import AppKit
import Core
import Foundation

@MainActor
enum IntegrationSettings {
    /// The settings a control panel may read and write, in the order the mirror presents them.
    static var curatedKeys: [AnySettingKey] {
        [
            // Power / triggers
            SettingKey.isAppEnabled.erased,
            SettingKey.isMouseHoldEnabled.erased,
            SettingKey.showMenuBarIcon.erased,
            SettingKey.startAtLogin.erased,
            // AI on/off only — provider, model and the API key stay in the app.
            SettingKey.isAIEnabled.erased,
            SettingKey.isDecisionsEnabled.erased,
            // Appearance
            SettingKey.popupTheme.erased,
            SettingKey.popupThemeColor.erased,
            SettingKey.popupAlignment.erased,
            SettingKey.popupVerticalPosition.erased,
            SettingKey.popupScale.erased,
            SettingKey.popupBarWidth.erased
        ]
    }

    /// Pauses the popup for `seconds` (default one hour), matching the menu bar's Pause.
    static func pause(
        seconds: TimeInterval = 3600,
        store: SettingsStore = DefaultSettingsStore.shared,
        now: Date = Date()
    ) {
        store.set(.pauseUntilTimestamp, value: now.timeIntervalSince1970 + seconds)
    }

    /// Clears any temporary pause.
    static func resume(store: SettingsStore = DefaultSettingsStore.shared) {
        store.set(.pauseUntilTimestamp, value: 0)
    }

    /// Restores the popup appearance settings the integration can write to their defaults.
    static func resetAppearance(store: SettingsStore = DefaultSettingsStore.shared) {
        store.set(.popupTheme, value: SettingKey.popupTheme.defaultValue)
        store.set(.popupThemeColor, value: SettingKey.popupThemeColor.defaultValue)
        store.set(.popupAlignment, value: SettingKey.popupAlignment.defaultValue)
        store.set(.popupVerticalPosition, value: SettingKey.popupVerticalPosition.defaultValue)
        store.set(.popupScale, value: SettingKey.popupScale.defaultValue)
        store.set(.popupBarWidth, value: SettingKey.popupBarWidth.defaultValue)
    }

    /// The side effects a plain store write does not carry: two toggles are mirrored through the
    /// same notifications the Preferences UI posts, the login item goes through `SMAppService`, and
    /// AI state is announced so the running UI refreshes.
    static func postSideEffects(forWrittenNames names: Set<String>, store: SettingsStore) {
        let notificationCenter = NotificationCenter.default
        if names.contains(SettingKey.isAppEnabled.name) {
            notificationCenter.post(
                name: .openClipEnabledStateChanged,
                object: store.get(.isAppEnabled)
            )
        }
        if names.contains(SettingKey.showMenuBarIcon.name) {
            notificationCenter.post(
                name: .openClipMenuBarVisibilityChanged,
                object: store.get(.showMenuBarIcon)
            )
        }
        if names.contains(SettingKey.startAtLogin.name) {
            LaunchAtLoginManager.shared.isEnabled = store.get(.startAtLogin)
        }
        if names.contains(SettingKey.isAIEnabled.name) {
            AIServiceManager.shared.objectWillChange.send()
        }
    }
}
