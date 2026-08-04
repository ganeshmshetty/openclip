// KeychainActionOptionStore.swift
// OpenClip
//
// Composite option store backing extension action configuration (Phase 7). Secret options route
// to the macOS Keychain via KeychainStore — never UserDefaults — keyed by
// `ActionOptionKey.keychainAccount`; empty secret values delete the Keychain entry. Everything
// else delegates to SettingsActionOptionStore under the same `action.<id>.option.<optID>` key.
// This is the store injected into DefaultActionFactory (AppDelegate) and used by the config UI, so
// secrets never reach UserDefaults from any runtime path. No migration: there are no legacy secrets.
import Foundation
import Core

public struct KeychainActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable {
    private let settings = SettingsActionOptionStore()

    public init() {}

    public func stringValue(actionID: String, option: ExtensionOption) -> String {
        if option.type == .secret {
            let account = ActionOptionKey.keychainAccount(actionID: actionID, optionID: option.identifier)
            if let stored = KeychainStore.get(account: account), !stored.isEmpty { return stored }
            return option.defaultValue ?? ""
        }
        return settings.stringValue(actionID: actionID, option: option)
    }

    public func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        if option.type == .secret {
            let account = ActionOptionKey.keychainAccount(actionID: actionID, optionID: option.identifier)
            if value.isEmpty {
                _ = KeychainStore.delete(account: account)
            } else {
                _ = KeychainStore.set(value, account: account)
            }
            return
        }
        settings.setStringValue(value, actionID: actionID, option: option)
    }

    public func clearValue(actionID: String, option: ExtensionOption) {
        if option.type == .secret {
            _ = KeychainStore.delete(account: ActionOptionKey.keychainAccount(actionID: actionID, optionID: option.identifier))
        } else {
            settings.clearValue(actionID: actionID, option: option)
        }
    }
}
