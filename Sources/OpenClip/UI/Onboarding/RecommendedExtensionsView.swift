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
    /// Curated featured extensions, mirroring the website's Recommended section
    /// (`CURATED_RECOMMENDED_IDS` in web/src/app/extensions/ExtensionsContent.tsx).
    private static let curatedRecommendedIDs = [
        "com.openclip.quick-translate",  // Quick Translate (inline, no redirect)
        "com.openclip.wordcount",       // Word & Character Count
        "com.openclip.speakselection",  // Speak Selection (system TTS, no redirect)
        "com.openclip.obsidiancapture", // Obsidian Capture
        "com.openclip.applereminders",  // Apple Reminders
        "com.openclip.githubsearch",    // GitHub Search
    ]

    @StateObject private var viewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init() {}

    private var installedExtensionCount: Int {
        ActionIdentity.installedPackageIDs(in: coordinator.actions).count
    }

    private var recommended: [ExtensionItem] {
        // Curated picks in declared order first, then fill remaining slots by downloads.
        let byID = Dictionary(viewModel.extensions.map { ($0.id.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })
        let curated = Self.curatedRecommendedIDs.compactMap { byID[$0.lowercased()] }
        var chosen = Set(curated.map { $0.id.lowercased() })
        let rest = viewModel.extensions
            .filter { chosen.insert($0.id.lowercased()).inserted }
            .sorted { $0.downloadCount > $1.downloadCount }
        return Array((curated + rest).prefix(6))
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
            // One request for the whole catalog (API caps limit at 100) so every
            // curated pick resolves regardless of alphabetical position.
            await viewModel.resetAndFetch(limit: 100)
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
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL, source: ExtensionSource.package.rawValue)
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
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @State private var isInstalling = false
    @State private var isUninstalling = false
    @State private var installError: String? = nil

    private var matchingInstalledAction: (any Action)? {
        coordinator.actions.first { action in
            let actID = action.id.lowercased()
            let itemID = item.id.lowercased()
            return actID == itemID || actID.hasPrefix(itemID + ".")
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let urlString = item.iconURL, let url = URL(string: urlString) {
                    RemoteTemplateIcon(url: url)
                        .frame(width: 18, height: 18)
                        .foregroundColor(.accentColor)
                } else {
                    AnyIconView(iconId: item.icon.hasPrefix("symbol:") ? String(item.icon.dropFirst(7)) : item.icon)
                        .frame(width: 18, height: 18)
                        .foregroundColor(.accentColor)
                }
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
                        isUninstalling = true
                        Task {
                            do {
                                try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                            } catch {
                                Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                            }
                            isUninstalling = false
                            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                        }
                    }
                }) {
                    if isUninstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(isUninstalling)
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
                            ExtensionManager.shared.prepareInstall(source: "store", packageID: item.id)
                            _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                            await ExtensionUpdateManager.shared.checkForUpdates()
                            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
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
