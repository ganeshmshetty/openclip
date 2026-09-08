// ExtensionsAPIClient.swift
// OpenClip
//
// Interacts with the remote OpenClip extension store API to fetch, search, and download available extensions.
import Foundation

public final class ExtensionsAPIClient: Sendable {
    public static let shared = ExtensionsAPIClient()
    public let baseURL: URL
    /// TTL'd page cache shared by every consumer (Store tab, onboarding, update checks).
    /// Nil disables caching (tests); the default instance survives view/tab recreation.
    private let cache: ExtensionStoreCache?

    public init(baseURL: URL = URL(string: "https://www.getopenclip.app/api/v1/extensions")!,
                cache: ExtensionStoreCache? = ExtensionStoreCache.shared) {
        self.baseURL = baseURL
        self.cache = cache
    }

    public func buildURL(query: String = "", page: Int = 1, limit: Int = 12) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespaces)))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    public func invalidateCache() async {
        await cache?.removeAll()
        URLCache.shared.removeAllCachedResponses()
    }

    public func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        try await fetchExtensions(query: query, page: page, limit: limit, ignoreCache: false)
    }

    public func fetchExtensions(query: String = "", page: Int = 1, limit: Int = Constants.storePageLimit, ignoreCache: Bool = false) async throws -> ExtensionsPageResponse {
        if !ignoreCache, let cached = await cache?.response(baseURL: baseURL.absoluteString, query: query, page: page, limit: limit) {
            return cached
        }

        guard let url = buildURL(query: query, page: page, limit: limit) else {
            throw NSError(domain: "ExtensionsAPIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"])
        }

        var request = URLRequest(url: url)
        if ignoreCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ExtensionsAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Server returned non-200 status"])
        }

        let decoded = try JSONDecoder().decode(ExtensionsPageResponse.self, from: data)
        await cache?.store(decoded, baseURL: baseURL.absoluteString, query: query, page: page, limit: limit)
        return decoded
    }
}

/// Page source for store UI; lets tests stub latency/ordering without touching the network.
public protocol ExtensionStoreFetching: Sendable {
    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse
    func fetchExtensions(query: String, page: Int, limit: Int, ignoreCache: Bool) async throws -> ExtensionsPageResponse
    func invalidateCache() async
}

extension ExtensionStoreFetching {
    public func fetchExtensions(query: String, page: Int, limit: Int, ignoreCache: Bool) async throws -> ExtensionsPageResponse {
        try await fetchExtensions(query: query, page: page, limit: limit)
    }

    public func invalidateCache() async {}
}

extension ExtensionsAPIClient: ExtensionStoreFetching {}
