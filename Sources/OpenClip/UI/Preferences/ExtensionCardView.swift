// ExtensionCardView.swift
// OpenClip
//
// The store list row for a single extension listing (icon, name, author, description,
// and install/uninstall actions). Formatted in native macOS table style.
import SwiftUI
import Core

struct ExtensionCardView: View {
    let item: ExtensionItem
    let isFeaturedExplicit: Bool?

    init(item: ExtensionItem, isFeatured: Bool? = nil) {
        self.item = item
        self.isFeaturedExplicit = isFeatured
    }

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
        isFeaturedExplicit ?? ExtensionsStoreViewModel.isFeatured(item)
    }

    /// Byline, download count and publication date on one quiet line under the description. The
    /// last two are what the Store sorts by, so a sorted list can be read without guessing why it
    /// is in that order.
    private var metadataLine: String {
        var parts: [String] = []
        if !item.author.isEmpty {
            parts.append(item.author)
        }
        if item.downloadCount == 1 {
            parts.append(String(localized: "\(formattedDownloadCount(item.downloadCount)) download"))
        } else if item.downloadCount > 1 {
            parts.append(String(localized: "\(formattedDownloadCount(item.downloadCount)) downloads"))
        }
        if let published = item.publishedDate {
            parts.append(String(localized: "Added \(published.formatted(.dateTime.day().month(.abbreviated).year()))"))
        }
        return parts.joined(separator: " · ")
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

            // Three levels, three weights: the name is what you scan, the
            // description is what you read, and the byline and download count
            // are only there once something has caught your eye. They used to be
            // the same grey as the description, and the byline sat on the name's
            // line, so all three competed at once.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if isFeatured {
                        Image(systemName: "rosette")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .help(String(localized: "Featured"))
                            .accessibilityLabel(String(localized: "Featured"))
                    }
                }

                if let err = installError {
                    Text("⚠︎ \(err)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(item.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            // Right Action Buttons
            HStack(spacing: 8) {
                if isInstalled, updateManager.updatablePackageIDs.contains(item.id) {
                    Button(action: {
                        isUpdating = true
                        installError = nil
                        Task {
                            do {
                                try await updateManager.update(packageID: item.id)
                            } catch {
                                installError = error.localizedDescription
                            }
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

                StoreActionButton(
                    item: item,
                    isInstalled: isInstalled,
                    isInstalling: isInstalling,
                    isUninstalling: isUninstalling,
                    onInstall: {
                        performInstall()
                    },
                    onUninstall: {
                        performUninstall()
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func performInstall() {
        guard let url = URL(string: item.downloadURL) else {
            installError = String(localized: "Invalid download URL.")
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isInstalling = true
        }
        installError = nil
        Task {
            let startTime = Date()
            do {
                ExtensionManager.shared.prepareInstall(source: "store", packageID: item.id)
                _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                await updateManager.checkForUpdates()
            } catch {
                installError = error.localizedDescription
            }
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.3 {
                try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isInstalling = false
            }
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        }
    }

    private func performUninstall() {
        guard let action = matchingInstalledAction else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isUninstalling = true
        }
        installError = nil
        Task {
            let startTime = Date()
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
            } catch {
                installError = error.localizedDescription
                Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
            }
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.3 {
                try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isUninstalling = false
            }
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        }
    }
}

// MARK: - Store Action Button

private struct StoreActionButton: View {
    let item: ExtensionItem
    let isInstalled: Bool
    let isInstalling: Bool
    let isUninstalling: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    private var isLoading: Bool {
        isInstalling || isUninstalling
    }

    var body: some View {
        Button {
            if isInstalled {
                onUninstall()
            } else {
                onInstall()
            }
        } label: {
            ZStack {
                if isInstalling {
                    SpinningArc(color: .white)
                        .transition(.opacity)
                } else if isUninstalling {
                    SpinningArc(color: .secondary)
                        .transition(.opacity)
                } else if isInstalled {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(isInstalled ? Color.primary.opacity(0.06) : Color.accentColor)
            )
        }
        .buttonStyle(StoreActionButtonStyle())
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isInstalled)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .help(isInstalled ? String(localized: "Remove \(item.name)") : String(localized: "Install \(item.name)"))
        .accessibilityLabel(isInstalled ? String(localized: "Remove \(item.name)") : String(localized: "Install \(item.name)"))
    }
}

// MARK: - Store Action Button Style

private struct StoreActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}

// MARK: - Spinning Arc

private struct SpinningArc: View {
    let color: Color
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.82)
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}
