// InlineColorExport.swift
// OpenClip
//
// Exports a typed inline color as a plain-text hex file for the result card's Save action.
import Foundation
import Core

@MainActor
enum InlineColorExport {
    private static var stagedFiles: Set<URL> = []

    /// Writes the canonical hex to a temporary `.txt` file and returns its URL. The caller hands
    /// the file to the normal `.saveFile` delivery path.
    static func writeText(_ color: InlineColor) -> URL? {
        let filename = "OpenClip Color \(String(color.hex.dropFirst())).txt"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try (color.hex + "\n").write(to: url, atomically: true, encoding: .utf8)
            stagedFiles.insert(url)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    static func removeStagedFile(_ url: URL) {
        guard stagedFiles.remove(url) != nil else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
