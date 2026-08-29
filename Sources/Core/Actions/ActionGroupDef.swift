// ActionGroupDef.swift
// OpenClip
//
// Pure domain model representing the persistent definition of a custom action group.
import Foundation

public struct ActionGroupDef: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var title: String
    public var iconName: String
    public var memberActionIDs: [String]

    public init(id: String, title: String, iconName: String, memberActionIDs: [String]) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.memberActionIDs = memberActionIDs
    }

    public static func encode(_ groups: [ActionGroupDef]) throws -> Data {
        try JSONEncoder().encode(groups)
    }

    public static func decode(from data: Data) throws -> [ActionGroupDef] {
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([ActionGroupDef].self, from: data)
    }

    public static func decodeOrEmpty(from data: Data?) -> [ActionGroupDef] {
        guard let data, !data.isEmpty else { return [] }
        return (try? decode(from: data)) ?? []
    }
}
