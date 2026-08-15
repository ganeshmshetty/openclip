// ExtensionPackageHashResolver.swift
// OpenClip
//
// Content hashing for the tamper-watch. A manifest package's digest covers the manifest bytes
// followed by each referenced script file's bytes (recursively through sub-actions), so any edit
// to the manifest or a script it runs changes the hash. Standalone scripts hash the file bytes.
// Pure Core — no AppKit/SwiftUI.
import Foundation

public enum ExtensionPackageHashResolver {
    /// SHA-256 over the manifest bytes then each referenced script file's bytes, in declaration
    /// order (recursively through sub-actions). Never nil for a readable manifest.
    public static func packageHash(manifestURL: URL, manifest: ExtensionMetadata) -> String? {
        guard let manifestData = try? Data(contentsOf: manifestURL) else { return nil }
        var payload = manifestData
        let directory = manifestURL.deletingLastPathComponent()
        for name in referencedScriptNames(actions: manifest.actions) {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)) {
                payload.append(data)
            }
        }
        return ContentFingerprint.sha256Hex(payload)
    }

    public static func fileHash(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ContentFingerprint.sha256Hex(data)
    }

    /// Hash of the package backing an already-loaded action: manifest packages via
    /// `locateManifest`, standalone scripts via their script URL.
    public static func packageHash(for action: any Action, in directory: URL) -> String? {
        if let located = ExtensionManifestStore.locateManifest(for: action, in: directory) {
            return packageHash(manifestURL: located.manifestURL, manifest: located.manifest)
        }
        if let script = action as? ScriptAction {
            return fileHash(script.scriptURL)
        }
        return nil
    }

    /// Hash of the package identified by `packageID` in `directory`, resolving it by walking the
    /// directory exactly like the loader: manifest packages matched by identifier, standalone
    /// scripts by their synthesized id.
    public static func packageHash(forPackageID: String, in directory: URL) -> String? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for item in items {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let manifestFile = ExtensionManifestStore.manifestFileURL(in: item),
                      let manifest = ExtensionManifestStore.readManifest(at: manifestFile),
                      manifest.identifier == forPackageID else { continue }
                return packageHash(manifestURL: manifestFile, manifest: manifest)
            } else {
                let synthesized = "\(Constants.customIdentifierPrefix)\(item.lastPathComponent)"
                if synthesized == forPackageID {
                    return fileHash(item)
                }
                // A standalone script may declare its package id in its header; resolve by that
                // too, mirroring how the loader derives the action id.
                if declaredIdentifier(of: item) == forPackageID {
                    return fileHash(item)
                }
            }
        }
        return nil
    }

    /// The identifier a standalone script declares in its header (`# Identifier:`,
    /// `// Identifier:`, or lowercase `// identifier:`), trimmed like the loader does.
    private static func declaredIdentifier(of scriptURL: URL) -> String? {
        guard let content = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).prefix(Constants.maxHeaderLinesToScan)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(Constants.identifierPrefixHash)
                || trimmed.hasPrefix(Constants.identifierPrefixSlash)
                || trimmed.hasPrefix("// identifier:") {
                return String(trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last ?? "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func referencedScriptNames(actions: [ExtensionActionMetadata]) -> [String] {
        var names: [String] = []
        func visit(_ actions: [ExtensionActionMetadata]) {
            for action in actions {
                if let script = action.script, !script.isEmpty { names.append(script) }
                visit(action.subActions ?? [])
            }
        }
        visit(actions)
        return names
    }
}