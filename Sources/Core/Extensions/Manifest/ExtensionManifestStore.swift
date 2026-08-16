// ExtensionManifestStore.swift
// OpenClip
//
// Single shared home for extension-manifest I/O: the canonical manifest filenames, reading and
// writing `ExtensionMetadata` packages, and locating the manifest entry that backs a given
// `Action`. Both the extension loader (`ExtensionManager`) and the App-target edit/add sheets use
// this so manifest discovery and authoring never diverge. Pure Core — no AppKit/SwiftUI.
import Foundation

/// Identifies a single manifest entry inside a package: the manifest file plus the index of the
/// action metadata it describes.
public struct LocatedManifest: Sendable {
    public let manifestURL: URL
    public let manifest: ExtensionMetadata
    public let targetIndex: Int

    public init(manifestURL: URL, manifest: ExtensionMetadata, targetIndex: Int) {
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.targetIndex = targetIndex
    }
}

public enum ExtensionManifestStore {
    /// Manifest filenames checked, in priority order, inside a package directory.
    public static let candidateFileNames: [String] = [
        Constants.manifestFileName,        // openclip.json (canonical)
        Constants.legacyManifestFileName,  // manifest.json (legacy)
        "Config.json"                      // legacy
    ]

    /// Returns the first manifest file present in `directory` (by candidate priority), or nil.
    public static func manifestFileURL(in directory: URL) -> URL? {
        for name in candidateFileNames {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Decodes an `ExtensionMetadata` manifest from a file URL, or nil when unreadable/unparseable.
    public static func readManifest(at url: URL) -> ExtensionMetadata? {
        try? decodeManifest(at: url)
    }

    /// Decodes an `ExtensionMetadata` manifest from a file URL, surfacing read/decode failures so
    /// the loader can log them instead of silently skipping the package.
    public static func decodeManifest(at url: URL) throws -> ExtensionMetadata {
        try decodeManifest(from: Data(contentsOf: url))
    }

    /// Decodes an `ExtensionMetadata` manifest from raw data, so a caller that already holds the
    /// bytes (e.g. the loader, which also fingerprints them) decodes exactly what it fingerprinted.
    public static func decodeManifest(from data: Data) throws -> ExtensionMetadata {
        try JSONDecoder().decode(ExtensionMetadata.self, from: data)
    }

    /// Encodes and atomically writes a manifest. The stable formatting (pretty-printed, sorted
    /// keys) is defined here once so every writer produces byte-consistent packages.
    public static func writeManifest(_ manifest: ExtensionMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// Locates the manifest package that backs `action` in `directory`: the package whose
    /// identifier matches the action's chrome source (or, as a fallback for stray `.custom`
    /// actions, its id), then the manifest entry whose uniform action ID equals `action.id`.
    /// Only directory-backed manifest packages are considered; a standalone script file with the
    /// same identifier returns nil.
    public static func locateManifest(
        for action: any Action,
        in directory: URL = Constants.extensionsDirectory
    ) -> LocatedManifest? {
        let packageID: String
        if case .extensionPkg(let pid) = action.chrome.source {
            packageID = pid
        } else {
            packageID = action.id
        }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            Log.factory.error("Failed to read extensions directory at \(directory.path, privacy: .public)")
            return nil
        }
        for item in items {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            for name in candidateFileNames {
                let manifestURL = item.appendingPathComponent(name)
                guard let manifest = readManifest(at: manifestURL),
                      manifest.identifier == packageID else { continue }
                func matchesSubActions(_ subActions: [ExtensionActionMetadata], parentID: String) -> Bool {
                    for (subIndex, sub) in subActions.enumerated() {
                        let subID = "\(parentID).\(sub.id ?? String(subIndex))"
                        if action.id == subID { return true }
                        if let nested = sub.subActions, matchesSubActions(nested, parentID: subID) {
                            return true
                        }
                    }
                    return false
                }

                for (index, meta) in manifest.actions.enumerated() {
                    let actionID = ExtensionManager.uniformActionID(metadata: meta, manifest: manifest, index: index)
                    if actionID == action.id {
                        return LocatedManifest(manifestURL: manifestURL, manifest: manifest, targetIndex: index)
                    }
                    if let subActions = meta.subActions, matchesSubActions(subActions, parentID: actionID) {
                        return LocatedManifest(manifestURL: manifestURL, manifest: manifest, targetIndex: index)
                    }
                }
            }
        }
        return nil
    }

    /// Returns the first manifest whose identifier equals `packageID` under `directory`, or nil.
    public static func manifest(forPackageID: String, in directory: URL) -> ExtensionMetadata? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for item in items {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let manifestFile = manifestFileURL(in: item),
                  let manifest = readManifest(at: manifestFile),
                  manifest.identifier == forPackageID else { continue }
            return manifest
        }
        return nil
    }
}
