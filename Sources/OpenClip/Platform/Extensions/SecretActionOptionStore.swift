// SecretActionOptionStore.swift
// OpenClip
//
// Composite option store backing extension action configuration. Secret options route
// to SecretStore (~/.openclip/secrets.json) — never UserDefaults — keyed by
// `ActionOptionKey.defaultsKey`; empty secret values delete the entry. Everything
// else delegates to SettingsActionOptionStore under the same `action.<id>.option.<optID>` key.
import Foundation
import Core

public struct SecretActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable {
    private let settings = SettingsActionOptionStore()

    public init() {}

    public func stringValue(actionID: String, option: ExtensionOption) -> String {
        if option.type == .secret {
            let account = ActionOptionKey.defaultsKey(actionID: actionID, optionID: option.identifier)
            if let stored = SecretStore.get(account: account), !stored.isEmpty { return stored }
            return option.defaultValue ?? ""
        }
        return settings.stringValue(actionID: actionID, option: option)
    }

    public func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        if option.type == .secret {
            let account = ActionOptionKey.defaultsKey(actionID: actionID, optionID: option.identifier)
            if value.isEmpty {
                _ = SecretStore.delete(account: account)
            } else {
                _ = SecretStore.set(value, account: account)
            }
            return
        }
        settings.setStringValue(value, actionID: actionID, option: option)
    }

    public func clearValue(actionID: String, option: ExtensionOption) {
        if option.type == .secret {
            let account = ActionOptionKey.defaultsKey(actionID: actionID, optionID: option.identifier)
            _ = SecretStore.delete(account: account)
        } else {
            settings.clearValue(actionID: actionID, option: option)
        }
    }
}

/// Backwards compatibility alias
public typealias KeychainActionOptionStore = SecretActionOptionStore
