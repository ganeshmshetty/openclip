// CustomActionRepository.swift
// OpenClip
//
// Handles JSON file storage and retrieval for custom actions in the Application Support directory.
import Foundation

public final class CustomActionRepository: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("OpenClip", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("custom_actions.json")
        }
    }

    public func load() -> [CustomAction] {
        guard let data = try? Data(contentsOf: fileURL),
              let actions = try? JSONDecoder().decode([CustomAction].self, from: data) else {
            return []
        }
        return actions
    }

    public func save(_ actions: [CustomAction]) {
        if let data = try? JSONEncoder().encode(actions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
