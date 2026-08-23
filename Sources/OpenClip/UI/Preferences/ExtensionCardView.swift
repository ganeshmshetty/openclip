// ExtensionCardView.swift
// OpenClip
//
// The store grid card for a single extension listing (icon, name, author, description,
// install/uninstall). Split out of ExtensionsStoreView.swift.
import SwiftUI
import Core

struct ExtensionCardView: View {
    let item: ExtensionItem
    @State private var isInstalling = false
    @State private var installError: String? = nil
    @State private var showSuccess = false
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared

    private var matchingInstalledAction: (any Action)? {
        // Generated action IDs are "<manifest.identifier>.action.<n>"; store item.id is
        // "<manifest.identifier>". Require the separator so unrelated shorter ids cannot match.
        ActionCoordinator.shared.actions.first { action in
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading icon: normalized adaptive SVG from the publish pipeline when
            // available (rendered as a tintable template); falls back to a bare SF
            // Symbol or a deterministic letter tile.
            ZStack {
                if let urlString = item.iconURL, let url = URL(string: urlString) {
                    RemoteTemplateIcon(url: url)
                        .frame(width: 19, height: 19)
                        .foregroundColor(.primary)
                } else if let symbolName = bareSymbolName {
                    ActionIconView(icon: .symbol(symbolName), size: 18)
                        .foregroundColor(.accentColor)
                } else {
                    letterTile
                }
            }
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("@\(item.author)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let version = item.version {
                        Text("v\(version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let err = installError {
                    Text("⚠︎ \(err)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else {
                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle")
                Text("\(item.downloadCount)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if showSuccess || isInstalled {
                if isInstalled, updateManager.updatablePackageIDs.contains(item.id) {
                    Button(action: { Task { try? await updateManager.update(packageID: item.id) } }) {
                        Label("Update", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button(role: .destructive, action: {
                    if let action = matchingInstalledAction {
                        Task {
                            do {
                                try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                            } catch {
                                Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                            }
                            await MainActor.run {
                                showSuccess = false
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
                Button(isInstalling ? "Installing..." : "Install") {
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
                            showSuccess = true
                            await updateManager.checkForUpdates()
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
