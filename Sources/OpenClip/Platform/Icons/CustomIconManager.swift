// CustomIconManager.swift
// OpenClip
//
// Manages custom user-provided icons stored in ~/.openclip/custom_icons/.
// Supports importing icons from Finder, resolving website favicons,
// and listing saved custom icons.
import Foundation
import AppKit
import Core
import SDWebImage
import SDWebImageSVGCoder

public enum CustomIconError: LocalizedError, Sendable {
    case invalidURL
    case networkFailed(String)
    case invalidImageData
    case fileNotFound
    case unsupportedFileType

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Please enter a valid website URL or domain.")
        case .networkFailed(let message):
            let format = String(localized: "Failed to download favicon: %@")
            return String(format: format, message)
        case .invalidImageData:
            return String(localized: "The resolved file is not a valid image.")
        case .fileNotFound:
            return String(localized: "Source image file was not found.")
        case .unsupportedFileType:
            return String(localized: "Unsupported file format. Please choose a PNG, SVG, JPG, or ICNS file.")
        }
    }
}

@MainActor
public final class CustomIconManager: ObservableObject, Sendable {
    public static let shared = CustomIconManager()

    public let directoryURL: URL

    @Published public private(set) var customIcons: [String] = []

    public init(directoryURL: URL = Constants.customIconsDirectory) {
        self.directoryURL = directoryURL
        ensureDirectoryExists()
        scanCustomIcons()
    }

    /// Ensures the custom icons directory exists
    public func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    /// Scans the custom icons directory for image files, sorting most-recent first.
    public func scanCustomIcons() {
        ensureDirectoryExists()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            customIcons = []
            return
        }

        let sorted = contents.filter { url in
            let ext = "." + url.pathExtension.lowercased()
            return Constants.imageExtensions.contains(ext)
        }.sorted { urlA, urlB in
            let dateA = (try? urlA.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let dateB = (try? urlB.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return dateA > dateB
        }

        customIcons = sorted.map { "\(Constants.customIconPrefix)\($0.lastPathComponent)" }
    }

    /// Imports an image file selected from Finder into ~/.openclip/custom_icons/
    /// and returns its `custom:<filename>` identifier.
    @discardableResult
    public func importIcon(from sourceURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CustomIconError.fileNotFound
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard Constants.imageExtensions.contains("." + ext) else {
            throw CustomIconError.unsupportedFileType
        }

        // Validate that image data is readable
        guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
            throw CustomIconError.invalidImageData
        }

        let isValidImage = (NSImage(data: data) != nil) || (SDImageSVGCoder.shared.decodedImage(with: data, options: nil) != nil)
        guard isValidImage else {
            throw CustomIconError.invalidImageData
        }

        ensureDirectoryExists()

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let cleanBase = baseName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let shortId = UUID().uuidString.prefix(6).lowercased()
        let filename = "icon_\(cleanBase)_\(shortId).\(ext)"
        let destinationURL = directoryURL.appendingPathComponent(filename)

        try data.write(to: destinationURL, options: .atomic)
        LocalIconCache.shared.invalidate(for: destinationURL)
        scanCustomIcons()

        return "\(Constants.customIconPrefix)\(filename)"
    }

    /// Normalizes a user-entered URL or domain string into a clean host.
    public static func normalizeHost(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }

    /// Resolves a favicon for the provided website URL or domain, saves it to
    /// the custom icons directory, and returns the `custom:<filename>` identifier.
    @discardableResult
    public func resolveFavicon(from inputString: String) async throws -> String {
        guard let host = Self.normalizeHost(from: inputString) else {
            throw CustomIconError.invalidURL
        }

        // 1. Try Google's high-resolution favicon service (128x128 PNG)
        var googleComponents = URLComponents(string: "https://www.google.com/s2/favicons")
        googleComponents?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128")
        ]
        guard let googleURL = googleComponents?.url else {
            throw CustomIconError.invalidURL
        }
        var fetchedData: Data? = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: googleURL)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty {
                fetchedData = data
            }
        } catch {
            Log.icons.debug("Google favicon service failed for \(host): \(error.localizedDescription)")
        }

        // 2. Fallback to direct /favicon.ico if Google service returned nothing
        if fetchedData == nil {
            var directComponents = URLComponents()
            directComponents.scheme = "https"
            directComponents.host = host
            directComponents.path = "/favicon.ico"
            if let directURL = directComponents.url {
                do {
                    let (data, response) = try await URLSession.shared.data(from: directURL)
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty {
                        fetchedData = data
                    }
                } catch {
                    Log.icons.debug("Direct favicon.ico failed for \(host): \(error.localizedDescription)")
                }
            }
        }

        guard let data = fetchedData, !data.isEmpty else {
            throw CustomIconError.networkFailed(host)
        }

        // 3. Decode image and normalize to PNG
        guard let image = NSImage(data: data) else {
            throw CustomIconError.invalidImageData
        }

        let pngData: Data
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pngData = png
        } else {
            pngData = data
        }

        ensureDirectoryExists()

        let sanitizedHost = host.replacingOccurrences(of: "[^a-zA-Z0-9.-]", with: "_", options: .regularExpression)
        let filename = "favicon_\(sanitizedHost).png"
        let destinationURL = directoryURL.appendingPathComponent(filename)

        try pngData.write(to: destinationURL, options: .atomic)
        LocalIconCache.shared.invalidate(for: destinationURL)
        scanCustomIcons()

        return "\(Constants.customIconPrefix)\(filename)"
    }

    /// Deletes a custom icon from disk and refreshes the available icon list.
    public func deleteCustomIcon(named iconId: String) {
        let rawFilename = iconId.hasPrefix(Constants.customIconPrefix)
            ? String(iconId.dropFirst(Constants.customIconPrefix.count))
            : iconId
        let trimmedFilename = rawFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty,
              !trimmedFilename.contains("/"),
              (trimmedFilename as NSString).lastPathComponent == trimmedFilename else {
            return
        }

        let fileURL = directoryURL.appendingPathComponent(trimmedFilename)
        guard fileURL.resolvingSymlinksInPath() != directoryURL.resolvingSymlinksInPath(),
              Constants.isPathSafe(destinationURL: fileURL, baseDirectory: directoryURL) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
        LocalIconCache.shared.invalidate(for: fileURL)
        scanCustomIcons()
    }
}
