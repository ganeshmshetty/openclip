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

    static var decisionOpenRouterBaseURL: SettingKey<String> {
        SettingKey<String>("decisionOpenRouterBaseURL", defaultValue: "https://openrouter.ai/api/v1")
    }

    static var decisionOpenRouterModel: SettingKey<String> {
        SettingKey<String>("decisionOpenRouterModel", defaultValue: "openai/gpt-4o-mini")
    }

    static var decisionLayaCommand: SettingKey<String> {
        SettingKey<String>("decisionLayaCommand", defaultValue: "laya")
    }

    static var decisionToolPresetsJSON: SettingKey<String> {
        SettingKey<String>("decisionToolPresetsJSON", defaultValue: "")
    }

    static var decisionLiveAssistDebounceMS: SettingKey<String> {
        // Stored as string to keep SettingKey surface simple; parsed as Int in the manager.
        SettingKey<String>("decisionLiveAssistDebounceMS", defaultValue: "200")
    }
}
