// ExtensionsAPIClient.swift
// OpenClip
//
// Interacts with the remote OpenClip extension store API to fetch, search, and download available extensions.
import Foundation

public final class ExtensionsAPIClient: Sendable {
    public static let shared = ExtensionsAPIClient()
    public let baseURL: URL
    
    public init(baseURL: URL = URL(string: "https://getopenclip.vercel.app/api/v1/extensions")!) {
        self.baseURL = baseURL
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
    
    public func fetchExtensions(query: String = "", page: Int = 1, limit: Int = 12) async throws -> ExtensionsPageResponse {
        guard let url = buildURL(query: query, page: page, limit: limit) else {
            throw NSError(domain: "ExtensionsAPIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ExtensionsAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Server returned non-200 status"])
        }
        
        return try JSONDecoder().decode(ExtensionsPageResponse.self, from: data)
    }
}
