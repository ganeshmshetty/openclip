// SettingsCatalog+App.swift
// OpenClip
//
// App-target settings keys (AI provider config, presentation prefs, hotkeys) appended to the Core
// catalog. Hotkeys are persisted by the KeyboardShortcuts package under `KeyboardShortcuts_<name>`
// in the same UserDefaults domain, so exposing them as String keys brings them into the snapshot.
import Core
import Foundation

extension SettingsCatalog {
    static var appKeys: [AnySettingKey] {
        [
            SettingKey.showMenuBarIcon.erased,
            SettingKey.resultCardWidth.erased,
            SettingKey.resultCardHeight.erased,
            SettingKey.searchPaletteWidth.erased,
            SettingKey.searchPaletteHeight.erased,

            SettingKey.aiActiveProvider.erased,
            SettingKey.aiCloudService.erased,
            SettingKey.aiCloudCustomURL.erased,
            SettingKey.aiCloudModel.erased,
            SettingKey.aiCloudCustomModel.erased,
            SettingKey.aiLocalPreset.erased,
            SettingKey.aiLocalURL.erased,
            SettingKey.aiLocalModel.erased,
            SettingKey.aiLocalCustomModel.erased,
            SettingKey.aiCLIPreset.erased,
            SettingKey.aiCLICustomCommand.erased,
            SettingKey.aiCLIModel.erased,
            SettingKey.aiCLICustomModel.erased,
            SettingKey.aiCLICustomAuthCommand.erased,
            SettingKey.aiActionPresetsJSON.erased,

            SettingKey.decisionActiveProvider.erased,
            SettingKey.decisionJevBaseURL.erased,
            SettingKey.decisionLayaCommand.erased,
            SettingKey.decisionToolPresetsJSON.erased,
            SettingKey.decisionLiveAssistDebounceMS.erased
        ]
    }

    /// Keys for the KeyboardShortcuts package's UserDefaults entries. `actionIDs` adds the
    /// per-action hotkeys for the actions currently registered.
    static func hotkeyKeys(actionIDs: [String] = []) -> [AnySettingKey] {
        // `stringOrBoolKey` preserves the library's Bool `false` ("shortcut disabled") sentinel
        // alongside its encoded-String form, so a restore does not re-enable a disabled default.
        var keys: [AnySettingKey] = [
            .stringOrBoolKey(named: "KeyboardShortcuts_togglePopup")
        ]
        for row in 1...9 {
            keys.append(.stringOrBoolKey(named: "KeyboardShortcuts_paletteRow\(row)"))
        }
        for id in actionIDs {
            keys.append(.stringOrBoolKey(named: "KeyboardShortcuts_actionHotkey.\(id)"))
        }
        return keys
    }

    /// Everything: Core keys, App keys, and hotkeys (including the given per-action hotkeys).
    static func all(actionIDs: [String] = []) -> [AnySettingKey] {
        coreKeys + appKeys + hotkeyKeys(actionIDs: actionIDs)
    }
}
