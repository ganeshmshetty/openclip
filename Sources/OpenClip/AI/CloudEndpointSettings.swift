// CloudEndpointSettings.swift
// OpenClip
//
// Stores a base endpoint override per cloud provider.
import Core

enum CloudEndpointSettings {
    static func customURL(for provider: CloudServiceProvider, store: SettingsStore = DefaultSettingsStore.shared) -> String {
        let overrides = store.get(.aiCloudCustomURLs)
        if let value = overrides[provider.rawValue] {
            return value
        }
        if provider == .custom {
            return store.get(.aiCloudCustomURL)
        }
        return ""
    }

    static func setCustomURL(_ url: String, for provider: CloudServiceProvider, store: SettingsStore = DefaultSettingsStore.shared) {
        var overrides = store.get(.aiCloudCustomURLs)
        overrides[provider.rawValue] = url
        store.set(.aiCloudCustomURLs, value: overrides)
        if provider == .custom {
            store.set(.aiCloudCustomURL, value: url)
        }
    }

    static func defaultURL(for provider: CloudServiceProvider) -> String {
        provider.defaultBaseURL
    }

    /// Moves the single endpoint override to the Custom provider and clears cached model lists,
    /// which may have come from that override.
    static func migrateLegacyCustomURLIfNeeded(store: SettingsStore = DefaultSettingsStore.shared) {
        guard store.rawObject(forKey: SettingKey.aiCloudCustomURLs.name) == nil else { return }
        let legacy = store.get(.aiCloudCustomURL)
        var overrides: [String: String] = [:]
        if !legacy.isEmpty {
            overrides[CloudServiceProvider.custom.rawValue] = legacy
        }
        store.set(.aiCloudModelCache, value: "")
        store.set(.aiCloudCustomURLs, value: overrides)
    }
}
