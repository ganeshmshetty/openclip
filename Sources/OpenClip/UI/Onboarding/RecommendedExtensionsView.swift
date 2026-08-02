// RecommendedExtensionsView.swift
// OpenClip
//
// Compact "recommended extensions" picker used by the first-launch onboarding flow.
// Shows the store's top extensions in a single-column list with an Install File…
// button pinned at the top, so new users can get going without opening Preferences.
import SwiftUI
import Core

@MainActor
public struct RecommendedExtensionsView: View {
    @StateObject private var viewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init() {}

    private var installedExtensionCount: Int {
        coordinator.actions.filter { action in
            if case .extensionPkg = action.chrome.badge { return true }
            if case .extensionPkg = action.chrome.source { return true }
            return false
        }.count
    }

    private var recommended: [ExtensionItem] {
        // "Recommended" = the store's most-downloaded extensions from the first page.
        Array(viewModel.extensions.sorted { $0.downloadCount > $1.downloadCount }.prefix(6))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended Extensions")
                        .font(.system(size: 13, weight: .semibold))
                    Text(installedExtensionCount > 0
                         ? "\(installedExtensionCount) installed so far"
                         : "Install a few to get more actions in your popup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: openInstallExtensionPanel) {
                    Label("Install File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            if viewModel.extensions.isEmpty {
                VStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Couldn't load recommended extensions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recommended) { item in
                            RecommendedExtensionRow(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
            }
        }
        .task {
            await viewModel.resetAndFetch()
        }
    }

    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Extension to Install"
        panel.message = "Choose a .openclipext folder, .zip archive, or script file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Extension Install Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
}

@MainActor
private struct RecommendedExtensionRow: View {
    let item: ExtensionItem
    @State private var isInstalling = false
    @State private var installError: String? = nil

    private var matchingInstalledAction: (any Action)? {
        ActionCoordinator.shared.actions.first { action in
            let actID = action.id.lowercased()
            let itemID = item.id.lowercased()
            let actTitle = action.displayTitle.lowercased()
            let itemName = item.name.lowercased()
            return actID.hasPrefix(itemID) || itemID.hasPrefix(actID) || actTitle == itemName
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                AnyIconView(iconId: item.icon.hasPrefix("symbol:") ? String(item.icon.dropFirst(7)) : item.icon)
                    .frame(width: 18, height: 18)
                    .foregroundColor(.accentColor)
            }
            .frame(width: 34, height: 34)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let err = installError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .help(err)
            }

            if isInstalled {
                Button(role: .destructive, action: {
                    if let action = matchingInstalledAction {
                        Task {
                            try? await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                            await MainActor.run {
                                NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                            }
                        }
                    }
                }) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button(isInstalling ? "Installing…" : "Install") {
                    guard let url = URL(string: item.downloadURL) else {
                        installError = "Invalid download URL."
                        return
                    }
                    isInstalling = true
                    installError = nil
                    Task {
                        do {
                            _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                        } catch {
                            installError = error.localizedDescription
                        }
                        isInstalling = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
