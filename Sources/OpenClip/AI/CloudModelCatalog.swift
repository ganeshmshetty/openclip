// CloudModelCatalog.swift
// OpenClip
//
// Keeps the cloud model pickers current without a release: live `/models` results are filtered to
// chat models, ordered newest first, and cached per provider so the list is ready before the next fetch.
import Foundation
import Core

struct CloudModelEntry: Equatable, Sendable {
    let id: String
    let created: Int?
}

enum CloudModelCatalog {
    static let cacheLifetime: TimeInterval = 24 * 60 * 60

    private static let nonChatMarkers = [
        "embed", "whisper", "tts", "transcribe", "dall-e", "image", "imagen", "veo", "moderation",
        "realtime", "audio", "speech", "aqa", "guard", "rerank", "vision-preview", "search-preview",
        "computer-use", "davinci", "babbage", "instruct"
    ]

    /// Drops embedding, speech, image, moderation and other non-chat models the providers also list.
    static func isChatModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        return !nonChatMarkers.contains { lower.contains($0) }
    }

    /// Newest first by creation time when the provider reports it, otherwise by descending version-aware name.
    static func ordered(_ entries: [CloudModelEntry]) -> [String] {
        let sorted = entries.sorted { a, b in
            switch (a.created, b.created) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id.localizedStandardCompare(b.id) == .orderedDescending
            }
        }
        var seen = Set<String>()
        return sorted.map(\.id).filter { seen.insert($0).inserted }
    }

    // MARK: - Cache

    struct Snapshot: Codable, Equatable, Sendable {
        var fetchedAt: Date
        var models: [String]
    }

    static func cached(for provider: CloudServiceProvider, store: SettingsStore = DefaultSettingsStore.shared) -> Snapshot? {
        decode(store.get(.aiCloudModelCache))[provider.rawValue]
    }

    static func isFresh(_ snapshot: Snapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.fetchedAt) < cacheLifetime
    }

    static func save(_ models: [String], for provider: CloudServiceProvider, now: Date = Date(), store: SettingsStore = DefaultSettingsStore.shared) {
        guard !models.isEmpty else { return }
        var all = decode(store.get(.aiCloudModelCache))
        all[provider.rawValue] = Snapshot(fetchedAt: now, models: models)
        if let data = try? JSONEncoder().encode(all), let json = String(data: data, encoding: .utf8) {
            store.set(.aiCloudModelCache, value: json)
        }
    }

    private static func decode(_ json: String) -> [String: Snapshot] {
        guard let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Snapshot].self, from: data)) ?? [:]
    }

    /// Live list if present, then the cached one, then the built-in fallback; the saved model is always kept selectable.
    static func choices(live: [String], cached: Snapshot?, provider: CloudServiceProvider, current: String?) -> [String] {
        var list = !live.isEmpty ? live : (cached?.models ?? provider.defaultModels)
        if let current, !current.isEmpty, current != "default", current != "custom", !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }
}
