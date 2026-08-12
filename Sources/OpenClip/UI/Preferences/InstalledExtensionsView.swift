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
        return representatives
            .map { packageID, action in
                PackageRow(packageID: packageID, title: titles[packageID] ?? packageID, representative: action)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @State private var selectedExtensionID: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(action: {
                    presentInstallExtensionPanel()
                }) {
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
                                Text(package.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(package.packageID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

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
