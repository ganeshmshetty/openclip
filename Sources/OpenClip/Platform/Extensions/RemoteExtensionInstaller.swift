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
        let finalURL = await resolveDownloadURL(from: downloadURL, extensionID: extensionID)
        
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
    
    public nonisolated func resolveDownloadURL(from url: URL, extensionID: String) async -> URL {
        // If the URL is already a specific existing .zip file, verify via HEAD request
        let lastComponent = url.lastPathComponent
        if lastComponent.hasSuffix(".zip") && lastComponent != "raw.zip" && lastComponent != "Extensions.zip" {
            if await checkURLExists(url) {
                return url
            }
        }
        
        let nameKey = (extensionID.components(separatedBy: ".").last ?? extensionID).lowercased()
        
        // Query GitHub contents API dynamically to find exact case-sensitive zip filename
        let apiURLStr = url.deletingLastPathComponent().absoluteString
            .replacingOccurrences(of: "https://raw.githubusercontent.com/", with: "https://api.github.com/repos/")
            .replacingOccurrences(of: "/main/Extensions/", with: "/contents/Extensions")
            .replacingOccurrences(of: "/master/Extensions/", with: "/contents/Extensions")
            
        struct GHContentItem: Decodable {
            let name: String
            let download_url: String
        }
        
        if let apiURL = URL(string: apiURLStr),
           let (data, _) = try? await URLSession.shared.data(from: apiURL),
           let items = try? JSONDecoder().decode([GHContentItem].self, from: data) {
            for item in items where item.name.hasSuffix(".zip") {
                let nameWithoutExt = item.name.replacingOccurrences(of: ".openclipext.zip", with: "").lowercased()
                if nameWithoutExt == nameKey || nameWithoutExt.contains(nameKey) || nameKey.contains(nameWithoutExt) {
                    if let rawURL = URL(string: item.download_url), await checkURLExists(rawURL) {
                        return rawURL
                    }
                }
            }
        }

        // Fallback candidate case variations
        let baseURL = url.deletingLastPathComponent()
        let pascalKey = nameKey.capitalized
        let candidates = [
            "\(pascalKey).openclipext.zip",
            "\(nameKey).openclipext.zip"
        ]
        for candidate in candidates {
            let testURL = baseURL.appendingPathComponent(candidate)
            if await checkURLExists(testURL) {
                return testURL
            }
        }
        
        return url
    }

    private nonisolated func checkURLExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
