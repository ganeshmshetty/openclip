// RemoteExtensionInstaller.swift
// OpenClip
//
// Downloads and unpacks remote extension packages from the extension store into the local Application Support directory.
import Foundation
import Core

@MainActor
public final class RemoteExtensionInstaller: Sendable {
    public static let shared = RemoteExtensionInstaller()
    
    private init() {}
    
    public nonisolated static func isPathSafe(destinationURL: URL, baseDirectory: URL) -> Bool {
        let destPath = (destinationURL.path as NSString).standardizingPath
        let basePath = (baseDirectory.path as NSString).standardizingPath
        return destPath.hasPrefix(basePath)
    }
    
    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        let finalURL = resolveDownloadURL(from: downloadURL, extensionID: extensionID)
        
        guard finalURL.scheme?.lowercased() == "https" else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS URLs are supported"])
        }
        
        let (tempLocalURL, _) = try await URLSession.shared.download(from: finalURL)
        
        // URLSession downloads with a .tmp extension and may land inside ~/.openclip/extensions.
        // Rename to a proper .zip path in the system temp directory so installExtension
        // correctly recognises it as a zip archive.
        let zipTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip_ext_\(extensionID)_\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: zipTempURL)
        try FileManager.default.moveItem(at: tempLocalURL, to: zipTempURL)
        
        defer { try? FileManager.default.removeItem(at: zipTempURL) }
        let installedActions = try await ExtensionManager.shared.installExtension(from: zipTempURL)
        return installedActions
    }
    
    public nonisolated func resolveDownloadURL(from url: URL, extensionID: String) -> URL {
        let lastComponent = url.lastPathComponent
        if lastComponent.hasSuffix(".zip") && lastComponent != "raw.zip" && lastComponent != "Extensions.zip" {
            return url
        }
        
        let nameKey = extensionID.components(separatedBy: ".").last ?? extensionID
        let baseURL = url.deletingLastPathComponent()
        return baseURL.appendingPathComponent("\(nameKey).openclipext.zip")
    }
}
