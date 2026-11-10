// ManifestPackageValidation.swift
// OpenClip
//
// Package-aware checks that need filesystem access. Kept separate from the pure manifest schema
// validation so `ManifestValidator` stays free of file IO.
import Foundation

public enum ExtensionManifestPath {
    /// Package-relative path that stays inside the extension directory.
    public static func isSafeRelativePath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains(":") else {
            return false
        }
        let dummyBase = URL(fileURLWithPath: "/extension_root")
        let destination = dummyBase.appendingPathComponent(trimmed)
        guard Constants.isPathSafe(destinationURL: destination, baseDirectory: dummyBase) else {
            return false
        }
        return destination.standardized.path != dummyBase.standardized.path
    }
}

public enum ManifestPackageValidation {
    /// Validates predicate paths against the package directory, including symlink containment,
    /// regular-file status, and the 64 KiB size limit.
    public static func validate(_ manifest: ExtensionMetadata, directory: URL) -> [ManifestValidationIssue] {
        var issues: [ManifestValidationIssue] = []
        let canonicalDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let canonicalPath = canonicalDirectory.path.hasSuffix("/")
            ? canonicalDirectory.path : canonicalDirectory.path + "/"

        func visit(_ actions: [ExtensionActionMetadata], path: String) {
            for (index, action) in actions.enumerated() {
                let actionPath = "\(path)[\(index)]"
                if let predicate = action.requirements?.predicate {
                    let trimmed = predicate.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          trimmed.lowercased().hasSuffix(".js"),
                          ExtensionManifestPath.isSafeRelativePath(trimmed) else {
                        issues.append(ManifestValidationIssue(kind: .unsafePredicatePath(predicate), path: actionPath))
                        continue
                    }
                    let fileURL = canonicalDirectory.appendingPathComponent(trimmed)
                    let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
                    guard canonicalFile.path.hasPrefix(canonicalPath),
                          Constants.isPathSafe(destinationURL: canonicalFile, baseDirectory: canonicalDirectory) else {
                        issues.append(ManifestValidationIssue(kind: .unsafePredicatePath(predicate), path: actionPath))
                        continue
                    }
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: canonicalFile.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue,
                          let values = try? canonicalFile.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true else {
                        issues.append(ManifestValidationIssue(kind: .missingPredicateFile(predicate), path: actionPath))
                        continue
                    }
                    if let size = try? canonicalFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 64 * 1024 {
                        issues.append(ManifestValidationIssue(kind: .predicateTooLarge(predicate), path: actionPath))
                    }
                }
                if let subActions = action.subActions, !subActions.isEmpty {
                    visit(subActions, path: "\(actionPath).subActions")
                }
            }
        }
        visit(manifest.actions, path: "actions")
        return issues
    }
}
