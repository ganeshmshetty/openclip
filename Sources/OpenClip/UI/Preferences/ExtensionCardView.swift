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

    private var matchingInstalledAction: (any Action)? {
        // Generated action IDs are "<manifest.identifier>.action.<n>", store item.id is "<manifest.identifier>"
        // So we match when the action.id starts with item.id (e.g. "com.openclip.applemusic.action.0" starts with "com.openclip.applemusic")
        ActionCoordinator.shared.actions.first { action in
            let actID = action.id.lowercased()
            let itemID = item.id.lowercased()
            let actTitle = action.displayTitle(using: ActionCustomizationManager.shared).lowercased()
            let itemName = item.name.lowercased()
            return actID.hasPrefix(itemID) || itemID.hasPrefix(actID) || actTitle == itemName
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon + Name & Author
            HStack(spacing: 12) {
                ZStack {
                    AnyIconView(iconId: item.icon.hasPrefix("symbol:") ? String(item.icon.dropFirst(7)) : item.icon)
                        .frame(width: 18, height: 18)
                        .foregroundColor(.accentColor)
                }
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text("@\(item.author)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Description
            Text(item.description)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(.secondary)
                .frame(minHeight: 32, alignment: .topLeading)

            if let err = installError {
                Text("⚠︎ \(err)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Footer Row: Downloads Pill & Action Button
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                    Text("\(item.downloadCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

                Spacer()

                if showSuccess || isInstalled {
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
                                _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                                showSuccess = true
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
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
