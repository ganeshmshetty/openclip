// ActionOptionStore.swift
// OpenClip
//
// Defines the option read/write seam for extension action configuration and a SettingsStore-backed
// implementation. Reads/writes go through SettingKey/SettingsStore only — never UserDefaults directly.
import Foundation

/// Reads configured option values for an action. Implementations may back values in
/// UserDefaults (via SettingsStore) now, and Keychain for secret options later (Phase 7).
public protocol ActionOptionReading: Sendable {
    func stringValue(actionID: String, option: ExtensionOption) -> String
}

/// Writes configured option values for an action.
public protocol ActionOptionWriting: Sendable {
    func setStringValue(_ value: String, actionID: String, option: ExtensionOption)
    func clearValue(actionID: String, option: ExtensionOption)
}

/// Default option store backed by `SettingsStore`. Keys are stable (`action.<id>.option.<optID>`),
/// so no data migration is needed. `clearValue` writes an empty string because `SettingKey`
/// requires a non-optional defaultValue and `SettingsStore` has no removal API; an empty stored
/// value is treated as "unset" by `stringValue`, which then falls back to the option's default.
public struct SettingsActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable {
    private let store: any SettingsStore

    public init(store: any SettingsStore = DefaultSettingsStore.shared) {
        self.store = store
    }

    public func stringValue(actionID: String, option: ExtensionOption) -> String {
        let key = SettingKey.actionOption(actionID: actionID, optionID: option.identifier)
        let stored = store.get(key)
        guard !stored.isEmpty else { return option.defaultValue ?? "" }
        return stored
    }

    public func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        store.set(SettingKey.actionOption(actionID: actionID, optionID: option.identifier), value: value)
    }

    public func clearValue(actionID: String, option: ExtensionOption) {
        store.set(SettingKey.actionOption(actionID: actionID, optionID: option.identifier), value: "")
    }
}
