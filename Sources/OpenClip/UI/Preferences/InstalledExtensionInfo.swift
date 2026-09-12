// InstalledExtensionInfo.swift
// OpenClip
//
// One installed extension package as the Settings window sees it: its name and icon, the actions
// it contributes, and whether the trust gate is holding it back. Built from the action catalog,
// which is the one list that already knows what is installed and loaded — the sidebar lists these
// under Extensions, one page each, and the Actions list points at the same pages.

import Foundation
import Core

/// What an installed package's folder holds beyond the actions it registers: the manifest's
/// version, author and description, where the folder is, and whether it ships a README. Read off
/// the main thread by the settings window, which hands it to the extension's page and uses it to
/// decide what the toolbar's ellipsis menu offers.
struct ExtensionPackageDetails: Equatable {
    let packageID: String
    let manifest: ExtensionMetadata?
    let directoryURL: URL?
    let readmeURL: URL?

    /// Filenames treated as the package's README, in the order they are looked for.
    static let readmeNames = ["README.md", "readme.md", "README.markdown", "README.txt", "README"]

    static func empty(packageID: String) -> ExtensionPackageDetails {
        ExtensionPackageDetails(packageID: packageID, manifest: nil, directoryURL: nil, readmeURL: nil)
    }

    /// Walks the extensions directory for the package's folder. Runs off the main actor: it opens
    /// and decodes every manifest it passes.
    static func load(
        packageID: String,
        in directory: URL = Constants.extensionsDirectory
    ) async -> ExtensionPackageDetails {
        await Task.detached(priority: .utility) { () -> ExtensionPackageDetails in
            let fileManager = FileManager.default
            guard let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return .empty(packageID: packageID) }

            for item in items where !item.lastPathComponent.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      let manifestURL = ExtensionManifestStore.manifestFileURL(in: item),
                      let manifest = ExtensionManifestStore.readManifest(at: manifestURL),
                      manifest.identifier == packageID else { continue }

                let readme = readmeNames
                    .map(item.appendingPathComponent)
                    .first { fileManager.fileExists(atPath: $0.path) }

                return ExtensionPackageDetails(
                    packageID: packageID,
                    manifest: manifest,
                    directoryURL: item,
                    readmeURL: readme
                )
            }
            return .empty(packageID: packageID)
        }.value
    }
}

struct InstalledExtensionInfo: Identifiable {
    let packageID: String
    let name: String
    let icon: ActionIcon
    /// The group action that carries the package's sub-actions, when the package is a group.
    let containerActionID: String?
    /// The actions a user can run, in catalog order — without the group container and without
    /// the placeholder the trust gate registers for a package it is holding back.
    let commands: [any Action]
    let gatedReason: ExtensionGateReason?

    var id: String { packageID }

    var isGroup: Bool { containerActionID != nil }

    /// The id `ExtensionManager.uninstallExtension` matches the package by.
    var uninstallActionID: String {
        containerActionID ?? commands.first?.id ?? packageID
    }

    /// Every installed package present in `actions`, sorted by name.
    static func all(from actions: [any Action]) -> [InstalledExtensionInfo] {
        var order: [String] = []
        var buckets: [String: [any Action]] = [:]
        for action in actions {
            guard case .extensionPkg(let packageID) = action.chrome.source else { continue }
            guard !ActionIdentity.isAIPreset(action), !isCustomPackage(packageID) else { continue }
            if buckets[packageID] == nil {
                order.append(packageID)
            }
            buckets[packageID, default: []].append(action)
        }
        return order
            .compactMap { make(packageID: $0, actions: buckets[$0] ?? []) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func info(for packageID: String, in actions: [any Action]) -> InstalledExtensionInfo? {
        let members = actions.filter { action in
            guard case .extensionPkg(let id) = action.chrome.source else { return false }
            return id == packageID && !ActionIdentity.isAIPreset(action)
        }
        return make(packageID: packageID, actions: members)
    }

    /// GUI-authored custom actions are stored as single-action manifest packages too, so they load
    /// through the same path as extensions. They are the user's own actions, not an installed
    /// extension, and the Actions list is where they live.
    static func isCustomPackage(_ packageID: String) -> Bool {
        packageID.hasPrefix(Constants.customIdentifierPrefix) || packageID.hasPrefix("custom.")
    }

    private static func make(packageID: String, actions: [any Action]) -> InstalledExtensionInfo? {
        guard let first = actions.first else { return nil }
        let container = actions.first { $0.chrome.popupBehavior == .showSubActions }
        let gated = actions.lazy.compactMap { $0 as? GatedExtensionAction }.first
        let representative: any Action = container ?? gated.map { $0 as any Action } ?? first

        let name: String
        if case .extensionPkg(let badgeName) = representative.chrome.badge, !badgeName.isEmpty {
            name = badgeName
        } else {
            name = representative.title
        }

        let commands = actions.filter { $0.id != container?.id && !($0 is GatedExtensionAction) }

        return InstalledExtensionInfo(
            packageID: packageID,
            name: name,
            icon: representative.icon,
            containerActionID: container?.id,
            commands: commands,
            gatedReason: gated?.reason
        )
    }
}

/// What the trust gate's state means, in the user's words. Nil for a revoked package, which the
/// enable switch already explains by being off.
func extensionGateDescription(for reason: ExtensionGateReason) -> String? {
    switch reason {
    case .filesChanged:
        return String(localized: "This extension was modified externally. Toggle on to verify and re-enable.")
    case .notEnabled:
        return String(localized: "New extension found in folder. Toggle on to enable.")
    case .needsNewerApp(let required):
        return String(localized: "This extension requires OpenClip \(required) or newer.")
    case .revoked:
        return nil
    }
}
