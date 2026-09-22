// SettingKey+Decisions.swift
// OpenClip
//
// Settings keys for Decision provider configuration (peer to SettingKey+AI).
import Core

extension SettingKey where Value == String {
    static var decisionActiveProvider: SettingKey<String> {
        SettingKey<String>("decisionActiveProvider", defaultValue: DecisionProviderType.laya.rawValue)
    }

    static var decisionJevBaseURL: SettingKey<String> {
        SettingKey<String>("decisionJevBaseURL", defaultValue: "https://api.typesafe.ai/v1")
    }

    /// Laya checkpoint run by the bundled bridge: "english" or "multilingual".
    static var decisionLayaModel: SettingKey<String> {
        SettingKey<String>("decisionLayaModel", defaultValue: "english")
    }

    static var decisionToolPresetsJSON: SettingKey<String> {
        SettingKey<String>("decisionToolPresetsJSON", defaultValue: "")
    }

    static var decisionLiveAssistDebounceMS: SettingKey<String> {
        // Stored as string to keep SettingKey surface simple; parsed as Int in the manager.
        SettingKey<String>("decisionLiveAssistDebounceMS", defaultValue: "200")
    }
}
