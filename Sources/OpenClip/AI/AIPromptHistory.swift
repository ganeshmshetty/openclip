// AIPromptHistory.swift
// OpenClip
//
// The user's recent free-form AI instructions, most recent first, capped — what the Ask AI
// composer lists under its field so a prompt they keep reusing is one arrow key away. Recorded
// on every run; a prompt that gets saved as a permanent AI tool leaves the list (it is a preset
// from then on). Persisted through SettingsStore (`SettingKey.recentAIPrompts`).
import Foundation
import Combine
import Core

@MainActor
public final class AIPromptHistory: ObservableObject {
    public static let shared = AIPromptHistory()

    /// How many recent prompts are kept.
    public static let capacity = 8

    @Published public private(set) var prompts: [String]
    private let store: any SettingsStore

    public init(store: any SettingsStore = DefaultSettingsStore.shared) {
        self.store = store
        self.prompts = store.get(.recentAIPrompts)
    }

    /// Moves `prompt` to the front (case-insensitively deduplicated) and trims to `capacity`.
    public func record(_ prompt: String) {
        let updated = Self.recording(prompt, in: prompts)
        guard updated != prompts else { return }
        prompts = updated
        store.set(.recentAIPrompts, value: updated)
    }

    /// Drops `prompt` from the list (case-insensitively).
    public func remove(_ prompt: String) {
        let wanted = AIPromptText.instruction(from: prompt).lowercased()
        let updated = prompts.filter { $0.lowercased() != wanted }
        guard updated != prompts else { return }
        prompts = updated
        store.set(.recentAIPrompts, value: updated)
    }

    /// Pure rule behind `record`: the collapsed prompt goes first, an earlier copy (any case) is
    /// removed, and the list is trimmed to `capacity`. A blank prompt leaves the list alone.
    public static func recording(_ prompt: String, in list: [String], capacity: Int = capacity) -> [String] {
        let instruction = AIPromptText.instruction(from: prompt)
        guard !instruction.isEmpty else { return list }
        var updated = list.filter { $0.lowercased() != instruction.lowercased() }
        updated.insert(instruction, at: 0)
        return Array(updated.prefix(capacity))
    }
}
