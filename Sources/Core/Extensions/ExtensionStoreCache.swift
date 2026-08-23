// ExtensionStoreCache.swift
// OpenClip
//
// Small in-memory TTL cache for extension-store pages. The Store tab (and onboarding's
// recommended list) is torn down and recreated on every tab switch, so caching at the API
// layer — keyed by normalized query/page/limit — makes revisits render instantly instead of
// re-hitting the network, and repeated searches reuse overlapping prefixes. Pure Core — no
// AppKit/SwiftUI.
import Foundation

public actor ExtensionStoreCache {
    public static let shared = ExtensionStoreCache()

    private struct Entry {
        let response: ExtensionsPageResponse
        let cachedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval

    public init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    /// Returns the cached page for this key if present and fresh; expires lazily.
    public func response(baseURL: String, query: String, page: Int, limit: Int) -> ExtensionsPageResponse? {
        let key = Self.key(baseURL: baseURL, query: query, page: page, limit: limit)
        guard let entry = entries[key] else { return nil }
        guard entry.cachedAt.addingTimeInterval(ttl) > Date() else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.response
    }

    public func store(_ response: ExtensionsPageResponse, baseURL: String, query: String, page: Int, limit: Int) {
        entries[Self.key(baseURL: baseURL, query: query, page: page, limit: limit)] =
            Entry(response: response, cachedAt: Date())
    }

    /// Drops everything (tests, forced refreshes).
    public func removeAll() {
        entries.removeAll()
    }

    /// `baseURL` is part of the key: the shared cache instance is injected into every
    /// `ExtensionsAPIClient`, so two clients with different endpoints (tests vs production,
    /// staging) must never serve each other's pages.
    private static func key(baseURL: String, query: String, page: Int, limit: Int) -> String {
        "\(baseURL)|\(query.trimmingCharacters(in: .whitespaces).lowercased())|\(page)|\(limit)"
    }
}
