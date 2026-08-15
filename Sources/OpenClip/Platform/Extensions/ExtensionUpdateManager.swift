// ExtensionUpdateManager.swift
// OpenClip
//
// Manual-only update checks for store-sourced extensions. Fetches the store listing, compares
// versions via ExtensionUpdatePlanner, and applies updates through RemoteExtensionInstaller
// (which re-installs the package under the same id — a store action that re-trusts).
import Foundation
import Core
import Combine

@MainActor
public final class ExtensionUpdateManager: ObservableObject {
    public static let shared = ExtensionUpdateManager()

    @Published public private(set) var updatablePackageIDs: [String] = []
    @Published public private(set) var isChecking = false

    private init() {}

    /// Gathers installed store-package versions and asks the store for each page, then computes
    /// the updatable set. Idempotent; safe to call from the Reload button and Store tab.
    public func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let settings = DefaultSettingsStore.shared
        let sources = settings.get(.extensionSources)
        let storePackageIDs = sources.keys.filter { sources[$0] == "store" }.sorted()

        var installed: [InstalledPackageVersion] = []
        for packageID in storePackageIDs {
            let version = ExtensionManifestStore.manifest(forPackageID: packageID, in: Constants.extensionsDirectory)?.version
            installed.append(InstalledPackageVersion(packageID: packageID, installedVersion: version, source: "store"))
        }

        var allItems: [ExtensionItem] = []
        var page = 1
        var totalPages = 1
        while page <= totalPages {
            if let response = try? await ExtensionsAPIClient.shared.fetchExtensions(page: page, limit: 50) {
                allItems.append(contentsOf: response.extensions)
                totalPages = response.totalPages
                page += 1
            } else {
                break
            }
        }

        updatablePackageIDs = ExtensionUpdatePlanner.updatablePackageIDs(storeItems: allItems, installed: installed)
    }

    /// Updates one package: marks its source as store (already true) and re-installs from the
    /// store download URL. Because an update is a store action and the trust gate re-trusts
    /// non-revoked store packages, no extra trust write is needed.
    public func update(packageID: String) async throws {
        guard let item = await storeItem(for: packageID), let url = URL(string: item.downloadURL) else {
            throw NSError(domain: "ExtensionUpdateManager", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No store listing for \(packageID)."])
        }
        ExtensionManager.shared.prepareInstall(source: "store", packageID: packageID)
        _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: packageID)
        await checkForUpdates()
    }

    public func updateAll() async {
        for packageID in updatablePackageIDs {
            try? await update(packageID: packageID)
        }
        await checkForUpdates()
    }

    private func storeItem(for packageID: String) async -> ExtensionItem? {
        var page = 1
        var totalPages = 1
        while page <= totalPages {
            guard let response = try? await ExtensionsAPIClient.shared.fetchExtensions(page: page, limit: 50) else { break }
            if let match = response.extensions.first(where: { $0.id == packageID }) { return match }
            totalPages = response.totalPages
            page += 1
        }
        return nil
    }
}