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
    
    /// Store-controlled package hosts.
    nonisolated static let storeDownloadHosts: Set<String> = [
        "getopenclip.app",
        "www.getopenclip.app",
        "openclip.app",
    ]

    /// GitHub release assets redirect to one of these CDNs. They are not accepted as an initial source.
    nonisolated static let githubAssetHosts: Set<String> = [
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com",
    ]

    nonisolated static let githubReleaseHost = "github.com"
    nonisolated static let officialGitHubReleasePathPrefix =
        "/ganeshmshetty/openclip-extensions/releases/download/"

    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        Log.extensions.notice("Starting installation for extension '\(extensionID, privacy: .public)'. Initial API URL: \(downloadURL, privacy: .public)")

        guard Self.isAllowedSource(downloadURL) else {
            Log.extensions.error("URL is not an allowed extension source: \(downloadURL, privacy: .public)")
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Download source is not allowed"])
        }
        
        // Redirect delegate enforces the allowlist on every hop; URLSession follows redirects silently.
        let session = URLSession(
            configuration: .ephemeral,
            delegate: AllowlistRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        
        Log.extensions.notice("Downloading package from allowed source \(downloadURL, privacy: .public)")
        
        let (tempLocalURL, response) = try await session.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 500, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response received."])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw NSError(domain: "RemoteExtensionInstaller", code: 404, userInfo: [NSLocalizedDescriptionKey: "Download URL is not reachable: \(downloadURL.absoluteString)"])
            }
            throw NSError(domain: "RemoteExtensionInstaller", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
        }
        guard Self.isAllowedResponse(response) else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 403, userInfo: [NSLocalizedDescriptionKey: "Download redirected to an untrusted host"])
        }
        
        // Move the .tmp download to a .zip path so installExtension recognizes the archive.
        let zipTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip_ext_\(extensionID)_\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: zipTempURL)
        try FileManager.default.moveItem(at: tempLocalURL, to: zipTempURL)
        
        defer { try? FileManager.default.removeItem(at: zipTempURL) }
        let installedActions = try await ExtensionManager.shared.installExtension(from: zipTempURL)
        Log.extensions.notice("Successfully installed extension '\(extensionID, privacy: .public)'. Total actions added: \(installedActions.count)")
        return installedActions
    }
    
    nonisolated static func isAllowedSource(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        if storeDownloadHosts.contains(host) { return true }
        return host == githubReleaseHost && url.path.hasPrefix(officialGitHubReleasePathPrefix)
    }

    /// Redirects may land on the store hosts or GitHub's asset CDNs. GitHub itself stays scoped to
    /// the official release path so a different repository cannot supply a package.
    nonisolated static func isAllowedRedirect(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        if host == githubReleaseHost {
            return url.path.hasPrefix(officialGitHubReleasePathPrefix)
        }
        return storeDownloadHosts.contains(host) || githubAssetHosts.contains(host)
    }

    nonisolated private static func isAllowedResponse(_ response: URLResponse) -> Bool {
        guard let url = response.url else { return false }
        return isAllowedRedirect(url)
    }

    nonisolated private static func isHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.port == nil || url.port == 443
    }
    
    private nonisolated func checkURLExists(_ url: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                Log.extensions.error("HEAD check for \(url, privacy: .public) returned a non-HTTP response")
                return false
            }
            return http.statusCode == 200 && Self.isAllowedResponse(response)
        } catch {
            Log.extensions.error("HEAD check failed for \(url, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }
}

/// Refuses redirects that leave the HTTPS allowlist.
private final class AllowlistRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, RemoteExtensionInstaller.isAllowedRedirect(url) else {
            // Refusing the redirect cancels the task and fails the install.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
