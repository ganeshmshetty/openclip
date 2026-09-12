// ExtensionsModels.swift
// OpenClip
//
// Defines data transfer objects and models for extension store listings, categories, and download responses.
import Foundation

public struct ExtensionItem: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let author: String
    public let icon: String
    public let downloadCount: Int
    public let downloadURL: String
    public let version: String?
    /// Absolute URL to the normalized adaptive web icon (currentColor SVG) generated
    /// by the extensions publish pipeline; absent for older catalog snapshots.
    public let iconURL: String?
    /// ISO 8601 publication or release timestamp from catalog.json; nil if unavailable.
    public let publishedAt: String?

    public init(
        id: String,
        name: String,
        description: String,
        author: String,
        icon: String,
        downloadCount: Int,
        downloadURL: String,
        version: String? = nil,
        iconURL: String? = nil,
        publishedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.icon = icon
        self.downloadCount = downloadCount
        self.downloadURL = downloadURL
        self.version = version
        self.iconURL = iconURL
        self.publishedAt = publishedAt
    }

    /// `publishedAt` as a date, or nil when the catalogue did not carry one.
    public var publishedDate: Date? {
        Self.parsePublishedAt(publishedAt)
    }

    /// The catalogue writes an internet timestamp with an offset ("2026-08-20T22:00:51+05:30");
    /// a date-only value is accepted too, and anything else — or a snapshot from before the field
    /// existed — is nil rather than a guess. Pure, so the accepted shapes are pinned by tests.
    public static func parsePublishedAt(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }
        if let date = try? Date(trimmed, strategy: .iso8601.year().month().day()) { return date }
        return nil
    }
}

public struct ExtensionsPageResponse: Sendable, Codable {
    public let extensions: [ExtensionItem]
    public let featured: [ExtensionItem]?
    public let new: [ExtensionItem]?
    public let page: Int
    public let totalPages: Int
    public let totalCount: Int
    
    public init(extensions: [ExtensionItem], featured: [ExtensionItem]? = nil, new: [ExtensionItem]? = nil, page: Int, totalPages: Int, totalCount: Int) {
        self.extensions = extensions
        self.featured = featured
        self.new = new
        self.page = page
        self.totalPages = totalPages
        self.totalCount = totalCount
    }
}
