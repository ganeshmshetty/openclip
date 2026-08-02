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
        guard downloadURL.scheme?.lowercased() == "https" else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS URLs are supported"])
        }
        
        let (tempLocalURL, _) = try await URLSession.shared.download(from: downloadURL)
        let installedActions = try await ExtensionManager.shared.installExtension(from: tempLocalURL)
        try? FileManager.default.removeItem(at: tempLocalURL)
        return installedActions
    }
}
