// ExtensionPackageHashResolver.swift
// OpenClip
//
// Content hashing for the tamper-watch. A manifest package's digest covers the manifest bytes
// followed by each referenced script file's bytes (recursively through sub-actions), so any edit
// to the manifest or a script it runs changes the hash. Standalone scripts hash the file bytes.
// Pure Core — no AppKit/SwiftUI.
import Foundation

public enum ExtensionPackageHashResolver {
    /// SHA-256 over a framed sequence of components: the manifest first, then each referenced
    /// script file's bytes in declaration order (recursively through sub-actions). Every component
    /// is framed with its normalized relative path and an 8-byte big-endian length prefix for both
    /// the path and the bytes, so the payload can never be assembled ambiguously. Unreadable
    /// referenced scripts are skipped (as before); never nil for a readable manifest.
    public static func packageHash(manifestURL: URL, manifest: ExtensionMetadata) -> String? {
        guard let manifestData = try? Data(contentsOf: manifestURL) else { return nil }
        let directory = manifestURL.deletingLastPathComponent()
        let canonicalDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let canonicalDirPath = canonicalDirectory.path.hasSuffix("/") ? canonicalDirectory.path : canonicalDirectory.path + "/"
        var payload = Data()
        appendComponent(&payload, relativePath: manifestURL.lastPathComponent, data: manifestData)
        
        var visited = Set<String>()
        visited.insert(normalizedRelativePath(manifestURL.lastPathComponent))
        
        for name in referencedScriptNames(actions: manifest.actions) {
            let scriptURL = directory.appendingPathComponent(name)
            guard Constants.isPathSafe(destinationURL: scriptURL, baseDirectory: canonicalDirectory) else { continue }
            let canonicalScript = scriptURL.resolvingSymlinksInPath().standardizedFileURL
            guard canonicalScript.path.hasPrefix(canonicalDirPath) else { continue }
            let rel = String(canonicalScript.path.dropFirst(canonicalDirPath.count))
            let normalized = normalizedRelativePath(rel)
            visited.insert(normalized)
            if let data = try? Data(contentsOf: canonicalScript) {
                appendComponent(&payload, relativePath: normalized, data: data)
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: canonicalDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            var extraFiles: [(relativePath: String, url: URL)] = []
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
                guard canonicalFile.path.hasPrefix(canonicalDirPath) else { continue }
                let rel = String(canonicalFile.path.dropFirst(canonicalDirPath.count))
                let normalized = normalizedRelativePath(rel)
                if !visited.contains(normalized) {
                    extraFiles.append((relativePath: rel, url: canonicalFile))
                }
            }
            extraFiles.sort { $0.relativePath < $1.relativePath }
            for extra in extraFiles {
                if let data = try? Data(contentsOf: extra.url) {
                    appendComponent(&payload, relativePath: extra.relativePath, data: data)
                }
            }
        }
        
        return ContentFingerprint.sha256Hex(payload)
    }

    /// Appends a component framed as [path byte count][path bytes][data byte count][data bytes],
    /// with all lengths 8-byte big-endian so the framing is unambiguous regardless of contents.
    private static func appendComponent(_ payload: inout Data, relativePath: String, data: Data) {
        appendLengthPrefixed(&payload, Data(normalizedRelativePath(relativePath).utf8))
        appendLengthPrefixed(&payload, data)
    }

    private static func appendLengthPrefixed(_ payload: inout Data, _ bytes: Data) {
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(bytes)
    }

    /// Collapses redundant separators/`.`/`..` segments and forces `/` separators, keeping the
    /// path relative to the package directory.
    private static func normalizedRelativePath(_ path: String) -> String {
        var normalized = (path as NSString).standardizingPath
        if normalized.hasPrefix("/") {
            normalized = String(normalized.dropFirst())
        }
        return normalized
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
    /// Shared with uninstall matching — any code resolving a standalone script's package id
    /// must use this, never filename substring heuristics.
    static func declaredIdentifier(of scriptURL: URL) -> String? {
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