// IntegrationSettings.swift
// OpenClip
//
// The app-level side effects the inbound `openclip://` commands perform. There is deliberately no
// settings read/write surface: a URL scheme is unauthenticated, so it may only trigger the
// reversible pause/resume effects below.
import Core
import Foundation

@MainActor
enum IntegrationSettings {
    /// Pauses the popup for `seconds` (default one hour), matching the menu bar's Pause.
    static func pause(
        seconds: TimeInterval = 3600,
        store: SettingsStore = DefaultSettingsStore.shared,
        now: Date = Date()
    ) {
        store.set(.pauseUntilTimestamp, value: now.timeIntervalSince1970 + seconds)
    }

    /// Clears any temporary pause.
    static func resume(store: SettingsStore = DefaultSettingsStore.shared) {
        store.set(.pauseUntilTimestamp, value: 0)
    }
}
