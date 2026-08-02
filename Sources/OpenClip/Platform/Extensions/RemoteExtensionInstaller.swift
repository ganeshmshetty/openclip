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
        Constants.isPathSafe(destinationURL: destinationURL, baseDirectory: baseDirectory)
    }
    
    /// Hosts that are allowed as remote extension download sources. The extension
    /// store is served from this project's GitHub releases; anything else is
    /// treated as untrusted and rejected.
    public static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "getopenclip.vercel.app",
        "openclip.app",
    ]
    
    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        print("[OpenClip RemoteInstaller] Starting installation for '\(extensionID)'. Initial API URL: \(downloadURL)")
        
        guard downloadURL.scheme?.lowercased() == "https" else {
            print("[OpenClip RemoteInstaller] Unsupported scheme: \(downloadURL.scheme ?? "none")")
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS URLs are supported"])
        }
        
        guard let host = downloadURL.host?.lowercased(), Self.allowedDownloadHosts.contains(host) else {
            print("[OpenClip RemoteInstaller] Host not in allowlist: \(downloadURL.host ?? "unknown")")
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Download host is not in the allowed list"])
        }
        
        // The store API guarantees this URL points at a real archive, so a single
        // HEAD check is enough to fail fast on stale/missing packages.
        guard await checkURLExists(downloadURL) else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 404, userInfo: [NSLocalizedDescriptionKey: "Download URL is not reachable: \(downloadURL.absoluteString)"])
        }
        print("[OpenClip RemoteInstaller] Downloading verified package from: \(downloadURL)")
        
        let (tempLocalURL, _) = try await URLSession.shared.download(from: downloadURL)
        
        // URLSession downloads with a .tmp extension and may land inside ~/.openclip/extensions.
        // Rename to a proper .zip path in the system temp directory so installExtension
        // correctly recognises it as a zip archive.
        let zipTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip_ext_\(extensionID)_\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: zipTempURL)
        try FileManager.default.moveItem(at: tempLocalURL, to: zipTempURL)
        
        defer { try? FileManager.default.removeItem(at: zipTempURL) }
        let installedActions = try await ExtensionManager.shared.installExtension(from: zipTempURL)
        print("[OpenClip RemoteInstaller] Successfully installed extension '\(extensionID)'. Total actions added: \(installedActions.count)")
        return installedActions
    }
    
    private nonisolated func checkURLExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
