// ActionUsageStore.swift
// OpenClip
//
// Tracks how recently each action was used, MRU style (VS Code command-palette pattern):
// each `record` bumps a monotonically increasing counter per action ID, so a higher counter
// always means "used more recently". Persisted through `SettingsStore` so history survives
// launches. Search ranking consumes it only as a tie-break below match quality — a hot action
// can never outrank a better fuzzy match.
import Foundation

@MainActor
public final class ActionUsageStore {
    public static let shared = ActionUsageStore()

    private let settingsStore: SettingsStore
    private var cached: [String: Int]

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        self.cached = settingsStore.get(.actionUsageRecency)
    }

    /// The current recency map: action ID → counter (higher = more recent). Empty when unused.
    public var recency: [String: Int] { cached }

    /// Records one use of `actionID`, bumping its counter above every other action's.
    public func record(_ actionID: String) {
        let next = (cached.values.max() ?? 0) + 1
        cached[actionID] = next
        settingsStore.set(.actionUsageRecency, value: cached)
    }

    /// Clears all usage history.
    public func reset() {
        cached = [:]
        settingsStore.set(.actionUsageRecency, value: cached)
    }
}
