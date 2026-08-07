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

    private var installedExtensionActions: [any Action] {
        coordinator.actions.filter { ActionIdentity.isExtension($0) }
    }

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

            if installedExtensionActions.isEmpty {
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
                List {
                    ForEach(installedExtensionActions, id: \.id) { action in
                        HStack(spacing: 12) {
                            ZStack {
                                ActionIconView(icon: action.displayIcon(using: ActionCustomizationManager.shared), size: 16)
                                    .foregroundColor(.accentColor)
                            }
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.displayTitle(using: ActionCustomizationManager.shared))
                                    .font(.system(size: 13, weight: .semibold))

                                switch action.chrome.badge {
                                case .extensionPkg(let pkgName):
                                    Text(pkgName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                default:
                                    Text("Extension Package")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive, action: {
                                uninstallExtension(actionID: action.id)
                            }) {
                                Label("Uninstall", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                        .padding(.vertical, 6)
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
