// InlineColorExport.swift
// OpenClip
//
// Exports a typed inline color as a plain-text hex file for the result card's Save action.
import Foundation
import Core

@MainActor
enum InlineColorExport {
    /// Writes the canonical hex to a temporary `.txt` file and returns its URL. The caller hands
    /// the file to the normal `.saveFile` delivery path.
    static func writeText(_ color: InlineColor) -> URL? {
        let filename = "OpenClip Color \(String(color.hex.dropFirst())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try (color.hex + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
