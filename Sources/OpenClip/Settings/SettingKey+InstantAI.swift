// SettingKey+InstantAI.swift
// OpenClip
//
// The Instant AI prompt's memory: the last instruction, recalled with ↑ so a prompt that is used
// over and over is one key away. A popup preference, so it lives in the App target.
import Core

extension SettingKey where Value == String {
    /// The last instruction run from the Instant AI prompt (collapsed); empty when none yet.
    static var lastInstantAIPrompt: SettingKey<String> {
        SettingKey<String>("ai.instant.lastPrompt", defaultValue: "")
    }
}
