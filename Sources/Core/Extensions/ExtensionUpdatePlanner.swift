// ExtensionUpdatePlanner.swift
// OpenClip
//
// Decides which installed store packages have a newer version available. Pure Core — the app
// target gathers the inputs (store listings + installed manifest versions) and calls this.
import Foundation

public struct InstalledPackageVersion: Sendable, Equatable {
    public let packageID: String
    public let installedVersion: String?
    public let source: String

    public init(packageID: String, installedVersion: String?, source: String) {
        self.packageID = packageID
        self.installedVersion = installedVersion
        self.source = source
    }
}

public enum ExtensionUpdatePlanner {
    /// Store-sourced packages whose semver-parseable available version is strictly newer than the
    /// installed manifest version. Missing/unparseable versions on either side → not updatable.
    public static func updatablePackageIDs(storeItems: [ExtensionItem], installed: [InstalledPackageVersion]) -> [String] {
        let storeByID = Dictionary(uniqueKeysWithValues: storeItems.map { ($0.id, $0) })
        return installed.compactMap { pkg in
            guard pkg.source == "store",
                  let storeItem = storeByID[pkg.packageID],
                  let available = storeItem.version,
                  let installed = pkg.installedVersion,
                  let availableVersion = SemanticVersion.parse(available),
                  let installedVersion = SemanticVersion.parse(installed),
                  availableVersion > installedVersion else { return nil }
            return pkg.packageID
        }.sorted()
    }
}