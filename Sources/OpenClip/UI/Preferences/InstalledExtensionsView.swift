// InstalledExtensionsView.swift
// OpenClip
//
// The "Installed" sub-tab of the Actions tab: lists extension-sourced actions with
// per-row uninstall. Split out of ExtensionsStoreView.swift.
import SwiftUI
import Core

public struct InstalledExtensionsView: View {
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init() {}

    /// One row per installed extension **package**. A group + its sub-actions all belong to the
    /// same package, so they render as a single flat row (no nesting) and uninstall removes the
    /// whole package — matching how the extension appears in the store.
    private struct PackageRow: Identifiable {
        let packageID: String
        let title: String
        let representative: any Action
        let gated: GatedExtensionAction?
        let source: ExtensionSource
        var id: String { packageID }
    }

    private var installedPackages: [PackageRow] {
        var representatives: [String: any Action] = [:]
        var titles: [String: String] = [:]
        for action in coordinator.actions where ActionIdentity.isExtension(action) {
            guard let packageID = ActionIdentity.extensionPackageID(of: action) else { continue }
            representatives[packageID] = representatives[packageID] ?? action
            if titles[packageID] == nil, case .extensionPkg(let name) = action.chrome.badge {
                titles[packageID] = name
            }
        }
        let sources = DefaultSettingsStore.shared.get(.extensionSources)
        return representatives
            .map { packageID, action in
                let gated = action as? GatedExtensionAction
                let srcStr = sources[packageID] ?? ExtensionSource.developer.rawValue
                let source = ExtensionSource(rawValue: srcStr) ?? .developer
                return PackageRow(packageID: packageID, title: titles[packageID] ?? packageID, representative: action, gated: gated, source: source)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @State private var selectedExtensionID: String? = nil
    @State private var trustReview: TrustReviewTarget? = nil
    @State private var isReloading = false
    @State private var updatingPackageID: String? = nil
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                if !updateManager.updatablePackageIDs.isEmpty {
                    Button(action: { Task { await updateManager.updateAll() } }) {
                        Label("Update All", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button(action: { Task { await reloadExtensions() } }) {
                    Label(isReloading ? "Reloading…" : "Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isReloading)
                Button(action: { presentInstallExtensionPanel() }) {
                    Label("Install File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            if installedPackages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Extensions Installed")
                        .font(.headline)
                    Text("Browse the Store tab or click 'Install File...' to add extensions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedExtensionID) {
                    ForEach(installedPackages) { package in
                        HStack(spacing: 12) {
                            ZStack {
                                ActionIconView(icon: package.representative.displayIcon(using: ActionCustomizationManager.shared), size: 16)
                                    .foregroundColor(.accentColor)
                            }
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(package.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(sourceTag(for: package.source))
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                        .foregroundColor(.secondary)
                                }
                                Text(package.packageID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let gated = package.gated {
                                Text(badge(for: gated.reason))
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                                    .foregroundColor(.orange)
                            }
                            if let gated = package.gated {
                                Button(action: { trustReview = TrustReviewTarget(packageID: package.packageID, reason: gated.reason) }) {
                                    Label(reviewLabel(for: gated.reason), systemImage: "eye")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if updateManager.updatablePackageIDs.contains(package.packageID) {
                                Button(action: { Task { await updateOne(package.packageID) } }) {
                                    Label(updatingPackageID == package.packageID ? "Updating…" : "Update", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(updatingPackageID != nil)
                            }

                            Button(role: .destructive, action: {
                                uninstallExtension(actionID: package.representative.id)
                            }) {
                                Label("Uninstall", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                        .padding(.vertical, 6)
                        .tag(package.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(12)
        .sheet(item: $trustReview) { target in
            TrustModelView(model: TrustModelViewModel.load(packageID: target.packageID, reason: target.reason))
        }
    }

    private func reloadExtensions() async {
        isReloading = true
        await ExtensionManager.shared.loadExtensions()
        await ExtensionUpdateManager.shared.checkForUpdates()
        isReloading = false
        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
    }

    private func updateOne(_ packageID: String) async {
        updatingPackageID = packageID
        do {
            try await updateManager.update(packageID: packageID)
        } catch {
            Log.extensions.error("Update failed for '\(packageID, privacy: .public)': \(error.localizedDescription)")
        }
        updatingPackageID = nil
        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
    }

    private func badge(for reason: ExtensionGateReason) -> String {
        switch reason {
        case .notEnabled: return "New"
        case .filesChanged: return "Changed"
        case .revoked: return "Disabled"
        case .needsNewerApp: return "Needs Update"
        }
    }

    private func sourceTag(for source: ExtensionSource) -> String {
        switch source {
        case .store: return "Store"
        case .package: return "Package"
        case .developer, .local: return "Developer"
        }
    }

    private func reviewLabel(for reason: ExtensionGateReason) -> String {
        switch reason {
        case .revoked: return "Enable"
        default: return "Review"
        }
    }

    private func uninstallExtension(actionID: String) {
        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: actionID)
            } catch {
                Log.extensions.error("Failed to uninstall extension '\(actionID, privacy: .public)': \(error.localizedDescription)")
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
            }
        }
    }
}
