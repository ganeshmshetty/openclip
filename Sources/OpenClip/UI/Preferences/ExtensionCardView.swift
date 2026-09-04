// ExtensionCardView.swift
// OpenClip
//
// The store list row for a single extension listing (icon, name, author, description,
// and install/uninstall actions). Formatted in native macOS table style.
import SwiftUI
import Core

struct ExtensionCardView: View {
    let item: ExtensionItem
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared
    @State private var isInstalling = false
    @State private var isUninstalling = false
    @State private var isUpdating = false
    @State private var installError: String? = nil

    private var matchingInstalledAction: (any Action)? {
        // Generated action IDs are "<manifest.identifier>.action.<n>"; store item.id is
        // "<manifest.identifier>". Require the separator so unrelated shorter ids cannot match.
        coordinator.actions.first { action in
            let actID = action.id.lowercased()
            let itemID = item.id.lowercased()
            return actID == itemID || actID.hasPrefix(itemID + ".")
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    /// The SF Symbol name when the catalog icon string names one — either bare
    /// ("bold", "text.alignleft") or explicitly prefixed ("symbol:sparkles") —
    /// or nil for file references like "icon.svg" / remote ids like "simple-icons:swift".
    private var bareSymbolName: String? {
        var icon = item.icon
        if icon.hasPrefix("symbol:") { icon = String(icon.dropFirst("symbol:".count)) }
        guard !icon.isEmpty else { return nil }
        let lowered = icon.lowercased()
        guard !lowered.hasSuffix(".svg")
            && !lowered.hasSuffix(".png")
            && !icon.contains("/")
            && !icon.contains(":") else { return nil }
        return icon
    }

    /// Deterministic letter tile (hue hashed from the id) — the last-resort icon.
    private var letterTile: some View {
        let hue = {
            var h = 0
            for b in item.id.utf8 { h = (h &* 31 &+ Int(b)) % 360 }
            return max(h, 0)
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hue: Double(hue), saturation: 0.55, brightness: 0.75))
            Text(String(item.name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "?"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var isFeatured: Bool {
        ExtensionsStoreViewModel.isFeatured(item)
    }

    private var isBrandNew: Bool {
        ExtensionsStoreViewModel.isNew(item) && (item.version == nil || item.version == "1.0.0")
    }

    private func formattedDownloadCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            return thousands.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
        } else {
            return "\(count)"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Leading icon: normalized adaptive SVG from the publish pipeline when
            // available (rendered as a tintable template); falls back to a bare SF
            // Symbol or a deterministic letter tile.
            ZStack {
                if let urlString = item.iconURL, let url = URL(string: urlString) {
                    RemoteTemplateIcon(url: url)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.primary)
                } else if let symbolName = bareSymbolName {
                    ActionIconView(icon: .symbol(symbolName), size: 18)
                        .foregroundColor(.accentColor)
                } else {
                    letterTile
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(7)

            // Center Title & Description (clean 2-line layout without metadata clutter)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if isFeatured {
                        Image(systemName: "rosette")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .help(String(localized: "Featured"))
                            .accessibilityLabel(String(localized: "Featured"))
                    }

                    if isBrandNew {
                        Text(String(localized: "New"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !item.author.isEmpty {
                        Text("by @\(item.author)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if let err = installError {
                    Text("⚠︎ \(err)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else {
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            // Right Action Buttons
            HStack(spacing: 8) {
                if item.downloadCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8.5, weight: .medium))
                        Text(formattedDownloadCount(item.downloadCount))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.trailing, 2)
                }

                if isInstalled {
                    if updateManager.updatablePackageIDs.contains(item.id) {
                        Button(action: {
                            isUpdating = true
                            Task {
                                try? await updateManager.update(packageID: item.id)
                                isUpdating = false
                                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                            }
                        }) {
                            Label(isUpdating ? String(localized: "Updating…") : String(localized: "Update"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isUpdating)
                    }

                    Button(isUninstalling ? String(localized: "Removing…") : String(localized: "Remove")) {
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
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minWidth: 64)
                    .disabled(isUninstalling)
                    .help(String(localized: "Remove \(item.name)"))
                    .accessibilityLabel(String(localized: "Remove \(item.name)"))
                } else {
                    Button(isInstalling ? String(localized: "Installing…") : String(localized: "Install")) {
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
                                await updateManager.checkForUpdates()
                                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                            } catch {
                                installError = error.localizedDescription
                            }
                            isInstalling = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(minWidth: 64)
                    .disabled(isInstalling)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
