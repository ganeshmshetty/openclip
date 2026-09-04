// RecommendedExtensionsView.swift
// OpenClip
//
// Compact "recommended extensions" picker used by the first-launch onboarding flow.
// Shows the store's top extensions in card-based rows with live Install/Remove buttons.
import SwiftUI
import Core

@MainActor
public struct RecommendedExtensionsView: View {
    /// Curated featured extensions in priority order
    private static var curatedRecommendedIDs: [String] {
        ExtensionsStoreViewModel.curatedFeaturedIDs
    }

    private static let fallbackItems: [ExtensionItem] = [
        ExtensionItem(
            id: "com.openclip.quick-translate",
            name: "Quick Translate",
            description: "Translate selected text into your preferred language",
            author: "openclip",
            icon: "symbol:character.book.closed.fill",
            downloadCount: 1500,
            downloadURL: "https://www.getopenclip.app/api/v1/extensions/com.openclip.quick-translate/download"
        ),
        ExtensionItem(
            id: "com.openclip.wordcount",
            name: "Word & Character Count",
            description: "Count words, characters, and estimated reading time",
            author: "openclip",
            icon: "symbol:textformat.123",
            downloadCount: 1200,
            downloadURL: "https://www.getopenclip.app/api/v1/extensions/com.openclip.wordcount/download"
        ),
        ExtensionItem(
            id: "com.openclip.speakselection",
            name: "Speak Selection",
            description: "Read selected text aloud using macOS speech synthesis",
            author: "openclip",
            icon: "symbol:speaker.wave.2.fill",
            downloadCount: 950,
            downloadURL: "https://www.getopenclip.app/api/v1/extensions/com.openclip.speakselection/download"
        )
    ]

    @StateObject private var viewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init() {}

    private var recommended: [ExtensionItem] {
        if viewModel.extensions.isEmpty {
            return Self.fallbackItems
        }

        let byID = Dictionary(viewModel.extensions.map { ($0.id.lowercased(), $0) },
                              uniquingKeysWith: { first, _ in first })
        let curated = Self.curatedRecommendedIDs.compactMap { byID[$0.lowercased()] }
        var chosen = Set(curated.map { $0.id.lowercased() })
        let rest = viewModel.extensions
            .filter { chosen.insert($0.id.lowercased()).inserted }
            .sorted { $0.downloadCount > $1.downloadCount }
        return Array((curated + rest).prefix(3))
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(recommended) { item in
                RecommendedExtensionRow(item: item)
            }
        }
        .task {
            await viewModel.resetAndFetch(limit: 100)
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

    private var bareSymbolName: String {
        var icon = item.icon
        if icon.hasPrefix("symbol:") { icon = String(icon.dropFirst("symbol:".count)) }
        return icon.isEmpty ? "puzzlepiece.extension" : icon
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                if let urlString = item.iconURL, let url = URL(string: urlString) {
                    RemoteTemplateIcon(url: url)
                        .frame(width: 18, height: 18)
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: bareSymbolName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 28, height: 28)

            // Title & Description
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let err = installError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .help(err)
            }

            // Live Install / Installed state
            if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.trailing, 4)
            } else {
                Button {
                    guard let url = URL(string: item.downloadURL) else {
                        installError = String(localized: "Invalid download URL.")
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
                } label: {
                    if isInstalling {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing…")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Install")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
