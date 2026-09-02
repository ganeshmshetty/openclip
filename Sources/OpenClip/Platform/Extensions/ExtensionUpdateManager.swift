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
    /// Outcome of the most recent updateAll batch; nil until the first batch runs. UI can observe
    /// this to surface a summary toast (X succeeded, Y failed).
    @Published public private(set) var lastBatchResult: ExtensionUpdateBatchResult?

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
        let maxPages = 100
        var page = 1
        var totalPages = 1
        while page <= totalPages {
            // Finite bound so a pathological server-reported totalPages can't spin forever; normal
            // pagination still follows the server's totalPages.
            guard page <= maxPages,
                  let response = try? await ExtensionsAPIClient.shared.fetchExtensions(page: page, limit: 50) else { break }
            allItems.append(contentsOf: response.extensions)
            totalPages = response.totalPages
            page += 1
        }
        // Only reached past the last server page if every required page (and the bound) succeeded;
        // otherwise keep the previously published updatable set instead of computing on partial data.
        guard page > totalPages else { return }
        updatablePackageIDs = ExtensionUpdatePlanner.updatablePackageIDs(storeItems: allItems, installed: installed)
    }

    /// Updates one package: marks its source as store (already true) and re-installs from the
    /// store download URL. The gate no longer blanket-re-trusts store packages, so update
    /// explicitly re-trusts (and re-records the hash) after the reinstall unless the package was
    /// revoked — a revoked package stays revoked. If the reinstall fails, the pre-update trust
    /// state and recorded hash are restored so the package isn't left in the intermediate seen state.
    public func update(packageID: String) async throws {
        guard let item = await storeItem(for: packageID), let url = URL(string: item.downloadURL) else {
            throw NSError(domain: "ExtensionUpdateManager", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No store listing for \(packageID)."])
        }
        let settings = DefaultSettingsStore.shared
        let wasRevoked = settings.get(.extensionTrust)[packageID] == ExtensionTrustState.revoked.rawValue
        let originalTrust = settings.get(.extensionTrust)[packageID]
        let originalHash = settings.get(.extensionTrustHashes)[packageID]
        if !wasRevoked {
            // Pre-mark seen and drop the recorded hash so the intermediate load inside the
            // install doesn't fire a spurious tamper event for a legitimate update.
            var trust = settings.get(.extensionTrust)
            trust[packageID] = ExtensionTrustState.seen.rawValue
            settings.set(.extensionTrust, value: trust)
            var hashes = settings.get(.extensionTrustHashes)
            hashes.removeValue(forKey: packageID)
            settings.set(.extensionTrustHashes, value: hashes)
        }
        ExtensionManager.shared.prepareInstall(source: "store", packageID: packageID)
        do {
            _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: packageID)
        } catch {
            if !wasRevoked {
                if let originalTrust {
                    var trust = settings.get(.extensionTrust)
                    trust[packageID] = originalTrust
                    settings.set(.extensionTrust, value: trust)
                }
                if let originalHash {
                    var hashes = settings.get(.extensionTrustHashes)
                    hashes[packageID] = originalHash
                    settings.set(.extensionTrustHashes, value: hashes)
                }
            }
            throw error
        }
        if !wasRevoked {
            await ExtensionManager.shared.enablePackage(packageID: packageID)
        }
        await checkForUpdates()
    }

    /// Updates every package in `updatablePackageIDs`. Individual failures are logged and collected
    /// into the returned result rather than aborting the batch or being silently swallowed by `try?`.
    @discardableResult
    public func updateAll() async -> ExtensionUpdateBatchResult {
        var succeeded: [String] = []
        var failed: [String: String] = [:]
        for id in updatablePackageIDs {
            do {
                try await update(packageID: id)
                succeeded.append(id)
            } catch {
                failed[id] = error.localizedDescription
                Log.extensions.error("Failed to update extension '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        let result = ExtensionUpdateBatchResult(succeeded: succeeded, failed: failed)
        lastBatchResult = result
        await checkForUpdates()
        return result
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