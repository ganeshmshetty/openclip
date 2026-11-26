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
    nonisolated private static let officialGitHubReleaseSegments =
        officialGitHubReleasePathPrefix.split(separator: "/").map(String.init)

    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        Log.extensions.notice("Starting installation for extension '\(extensionID, privacy: .public)'. Initial API URL: \(downloadURL, privacy: .public)")

        guard Self.isAllowedSource(downloadURL) else {
            Log.extensions.error("URL is not an allowed extension source: \(downloadURL, privacy: .public)")
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Download source is not allowed"])
        }
        let allowsGitHubAssets = Self.isOfficialGitHubReleaseURL(downloadURL)

        // Redirect delegate enforces the allowlist on every hop; URLSession follows redirects silently.
        let session = URLSession(
            configuration: .ephemeral,
            delegate: AllowlistRedirectDelegate(allowsGitHubAssets: allowsGitHubAssets),
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
        guard Self.isAllowedResponse(response, allowsGitHubAssets: allowsGitHubAssets) else {
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
        return isOfficialGitHubReleaseURL(url)
    }

    /// Redirects may land on the store hosts or, only when the original source was the official
    /// GitHub release path, GitHub's asset CDNs.
    nonisolated static func isAllowedRedirect(_ url: URL, allowsGitHubAssets: Bool) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        if host == githubReleaseHost {
            return isOfficialGitHubReleaseURL(url)
        }
        if storeDownloadHosts.contains(host) { return true }
        return allowsGitHubAssets && githubAssetHosts.contains(host)
    }

    /// Rejects dot segments after repeated percent-decoding, so `..`, `%2e%2e`, and double-encoded
    /// variants cannot escape the official release path before the server normalizes them.
    nonisolated private static func isOfficialGitHubReleaseURL(_ url: URL) -> Bool {
        guard url.host?.lowercased() == githubReleaseHost else { return false }

        var decodedPath = url.path
        for _ in 0..<3 {
            guard let next = decodedPath.removingPercentEncoding, next != decodedPath else { break }
            decodedPath = next
        }

        let segments = decodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segments.count >= officialGitHubReleaseSegments.count,
              Array(segments.prefix(officialGitHubReleaseSegments.count)) == officialGitHubReleaseSegments else {
            return false
        }
        return segments.allSatisfy { segment in
            !segment.isEmpty
                && segment != "."
                && segment != ".."
                && !segment.contains("\\")
                && !segment.contains("%")
                && !segment.contains("\0")
        }
    }

    nonisolated private static func isAllowedResponse(_ response: URLResponse, allowsGitHubAssets: Bool) -> Bool {
        guard let url = response.url else { return false }
        return isAllowedRedirect(url, allowsGitHubAssets: allowsGitHubAssets)
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
            return http.statusCode == 200
                && Self.isAllowedResponse(response, allowsGitHubAssets: Self.isOfficialGitHubReleaseURL(url))
        } catch {
            Log.extensions.error("HEAD check failed for \(url, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }
}

/// Refuses redirects that leave the HTTPS allowlist.
private final class AllowlistRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowsGitHubAssets: Bool

    init(allowsGitHubAssets: Bool) {
        self.allowsGitHubAssets = allowsGitHubAssets
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              RemoteExtensionInstaller.isAllowedRedirect(url, allowsGitHubAssets: allowsGitHubAssets) else {
            // Refusing the redirect cancels the task and fails the install.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
