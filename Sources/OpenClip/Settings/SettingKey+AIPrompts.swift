// SettingKey+AIPrompts.swift
// OpenClip
//
// The Ask AI composer's recent-prompt list. A presentation preference of the popup (what the
// composer lists), so it lives in the App target next to the other popup keys rather than in Core.
import Core

extension SettingKey where Value == [String] {
    /// The user's recent free-form AI instructions, most recent first (see `AIPromptHistory`).
    static var recentAIPrompts: SettingKey<[String]> {
        SettingKey<[String]>("ai.recentPrompts", defaultValue: [])
    }
}
