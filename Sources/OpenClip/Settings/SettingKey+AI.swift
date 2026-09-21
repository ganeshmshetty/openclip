// SettingKey+AI.swift
// OpenClip
//
// Settings keys for AI provider configuration. These defaults live in the App target because
// they reference the provider preset enums; the key names match the values used before the
// settings surface was routed through SettingsStore.
import Core

extension SettingKey where Value == String {
    static var aiActiveProvider: SettingKey<String> {
        SettingKey<String>(
            "aiActiveProvider",
            defaultValue: AppleIntelligenceAvailability.isSupported ? AIProviderType.apple.rawValue : AIProviderType.local.rawValue
        )
    }

    static var aiCloudService: SettingKey<String> {
        SettingKey<String>("aiCloudService", defaultValue: CloudServiceProvider.openai.rawValue)
    }

    static var aiCloudCustomURL: SettingKey<String> {
        SettingKey<String>("aiCloudCustomURL", defaultValue: "")
    }

    static var aiCloudModel: SettingKey<String> {
        SettingKey<String>("aiCloudModel", defaultValue: "gpt-4o-mini")
    }

    static var aiCloudCustomModel: SettingKey<String> {
        SettingKey<String>("aiCloudCustomModel", defaultValue: "")
    }

    static var aiLocalPreset: SettingKey<String> {
        SettingKey<String>("aiLocalPreset", defaultValue: LocalLLMPreset.lmstudio.rawValue)
    }

    static var aiLocalURL: SettingKey<String> {
        SettingKey<String>("aiLocalURL", defaultValue: "http://localhost:1234/v1")
    }

    static var aiLocalModel: SettingKey<String> {
        SettingKey<String>("aiLocalModel", defaultValue: "default")
    }

    static var aiLocalCustomModel: SettingKey<String> {
        SettingKey<String>("aiLocalCustomModel", defaultValue: "")
    }

    static var aiCLIPreset: SettingKey<String> {
        SettingKey<String>("aiCLIPreset", defaultValue: CLIPreset.claude.rawValue)
    }

    static var aiCLICustomCommand: SettingKey<String> {
        SettingKey<String>("aiCLICustomCommand", defaultValue: "")
    }

    static var aiCLIModel: SettingKey<String> {
        SettingKey<String>("aiCLIModel", defaultValue: "default")
    }

    static var aiCLICustomModel: SettingKey<String> {
        SettingKey<String>("aiCLICustomModel", defaultValue: "")
    }

    static var aiCLICustomAuthCommand: SettingKey<String> {
        SettingKey<String>("aiCLICustomAuthCommand", defaultValue: "")
    }

    static var aiActionPresetsJSON: SettingKey<String> {
        SettingKey<String>("aiActionPresetsJSON", defaultValue: "")
    }
}
