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
    public let category: String
    public let downloadCount: Int
    public let downloadURL: String
    public let version: String?
    
    public init(
        id: String,
        name: String,
        description: String,
        author: String,
        icon: String,
        category: String,
        downloadCount: Int,
        downloadURL: String,
        version: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.icon = icon
        self.category = category
        self.downloadCount = downloadCount
        self.downloadURL = downloadURL
        self.version = version
    }
}

public struct ExtensionsPageResponse: Sendable, Codable {
    public let extensions: [ExtensionItem]
    public let page: Int
    public let totalPages: Int
    public let totalCount: Int
    
    public init(extensions: [ExtensionItem], page: Int, totalPages: Int, totalCount: Int) {
        self.extensions = extensions
        self.page = page
        self.totalPages = totalPages
        self.totalCount = totalCount
    }
}
