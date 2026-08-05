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
    public nonisolated static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com",
        "raw.githubusercontent.com",
        "getopenclip.vercel.app",
        "openclip.app",
    ]
    
    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        print("[OpenClip RemoteInstaller] Starting installation for '\(extensionID)'. Initial API URL: \(downloadURL)")
        
        guard Self.isAllowedSource(downloadURL) else {
            print("[OpenClip RemoteInstaller] Host not in allowlist: \(downloadURL.host ?? "unknown")")
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Download host is not in the allowed list"])
        }
        
        // Use a session with a redirect delegate so the HTTPS + host allowlist is applied to every
        // hop, not just the initial URL. URLSession silently follows redirects by default, which
        // would let an allowlisted source bounce the download to an attacker-controlled host.
        let session = URLSession(
            configuration: .ephemeral,
            delegate: AllowlistRedirectDelegate(allowedHosts: Self.allowedDownloadHosts),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        
        // The store API guarantees this URL points at a real archive, so a single
        // HEAD check is enough to fail fast on stale/missing packages.
        guard await checkURLExists(downloadURL, session: session) else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 404, userInfo: [NSLocalizedDescriptionKey: "Download URL is not reachable: \(downloadURL.absoluteString)"])
        }
        print("[OpenClip RemoteInstaller] Downloading verified package from: \(downloadURL)")
        
        let (tempLocalURL, response) = try await session.download(from: downloadURL)
        guard Self.isAllowedResponse(response, allowedHosts: Self.allowedDownloadHosts) else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 403, userInfo: [NSLocalizedDescriptionKey: "Download redirected to an untrusted host"])
        }
        
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
    
    nonisolated private static func isAllowedSource(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedDownloadHosts.contains(host) else { return false }
        return true
    }
    
    nonisolated private static func isAllowedResponse(_ response: URLResponse, allowedHosts: Set<String>) -> Bool {
        guard let url = response.url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host) else { return false }
        return true
    }
    
    private nonisolated func checkURLExists(_ url: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 && Self.isAllowedResponse(response, allowedHosts: Self.allowedDownloadHosts)
    }
}

/// Refuses URLSession redirects that leave the HTTPS allowlist, so a download can't
/// be bounced to an attacker-controlled host after the initial URL passes validation.
private final class AllowlistRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host) else {
            // Refusing the redirect cancels the task and fails the install.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
