// ExtensionPackagePage.swift
// OpenClip
//
// One installed extension's settings page: who made it, whether it is on, the actions it adds and
// the way into each one's settings, and the way to remove it. Reached from its row in the sidebar's
// Extensions group, from its group row in the Actions list, or from a package header there.
//
// This is what Raycast does with an extension — select it in the sidebar and everything about it
// is on one page — and it is the reason an extension is a sidebar destination rather than a gear on
// a list row.

import SwiftUI
import AppKit
import Core

@MainActor
struct ExtensionPackagePage: View {
    let packageID: String
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    /// Manifest details the action catalog does not carry (version, author, description). Read
    /// off the main thread when the page appears; nil for a standalone script extension.
    @State private var manifest: ExtensionMetadata?
    @State private var packageURL: URL?
    @State private var isConfirmingRemoval = false
    @State private var isRemoving = false
    @State private var isUpdating = false

    init(packageID: String, disabledActionIDs: Binding<Set<String>>, disabledPackages: Binding<Set<String>>) {
        self.packageID = packageID
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    private var info: InstalledExtensionInfo? {
        InstalledExtensionInfo.info(for: packageID, in: coordinator.actions)
    }

    var body: some View {
        Group {
            if let info {
                page(for: info)
            } else if isRemoving {
                // The package is going; the list it came from is where to land.
                Color.clear
            } else {
                // The package went away while its page was open (uninstalled from the Store, or its
                // folder was deleted). Show the list rather than an empty pane.
                Color.clear.onAppear { router.select(.customize) }
            }
        }
        .task(id: packageID) {
            await loadManifest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipExtensionsDidChange)) { _ in
            Task { await loadManifest() }
        }
    }

    private func page(for info: InstalledExtensionInfo) -> some View {
        Form {
            headerSection(info)
            actionsSection(info)
            manageSection(info)
        }
        .formStyle(.grouped)
    }

    // MARK: - Header

    private func headerSection(_ info: InstalledExtensionInfo) -> some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                ExtensionIconTile(icon: info.icon, tint: ExtensionTint.color(for: packageID), size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.name)
                        .font(.title3.weight(.semibold))
                    if let byline {
                        Text(byline)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let description = manifest?.localizedDescription?.resolve() ?? manifest?.description,
                       !description.isEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 12)

                Toggle("", isOn: ActionEnablement.packageBinding(
                    packageID: packageID,
                    gatedReason: info.gatedReason,
                    disabledPackages: $disabledPackages
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(String(localized: "Enable \(info.name)"))
            }
            .padding(.vertical, 6)

            if let reason = info.gatedReason, let text = extensionGateDescription(for: reason) {
                Label {
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// "Version 1.0.0 · OpenClip Team", whichever parts the manifest declares.
    private var byline: String? {
        var parts: [String] = []
        if let version = manifest?.version, !version.isEmpty {
            parts.append(String(localized: "Version \(version)"))
        }
        if let author = manifest?.author, !author.isEmpty {
            parts.append(author)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionsSection(_ info: InstalledExtensionInfo) -> some View {
        if !info.commands.isEmpty {
            Section {
                ForEach(info.commands, id: \.id) { action in
                    commandRow(action)
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Turn an action off to hide it from the popup bar. Open one to change its name, icon, shortcut and options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandRow(_ action: any Action) -> some View {
        let presentation = customizationManager.presented(action, surface: .table)

        return HStack(spacing: 10) {
            Button {
                router.push(.action(id: action.id))
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                    Text(presentation.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure Action")

            Toggle("", isOn: ActionEnablement.binding(
                for: action,
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(String(localized: "Enable \(presentation.title)"))

            Button {
                router.push(.action(id: action.id))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Configure \(presentation.title)"))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Manage

    private func manageSection(_ info: InstalledExtensionInfo) -> some View {
        Section {
            if let containerID = info.containerActionID {
                SettingsDisclosureRow {
                    router.push(.action(id: containerID))
                } content: {
                    SettingsRowLabel(
                        title: "Name and Icon in Popup Bar",
                        subtitle: "Rename the group or change the icon its actions sit behind.",
                        systemImage: "square.grid.2x2"
                    )
                }
            }

            if updateManager.updatablePackageIDs.contains(packageID) {
                SettingsRow(
                    title: "Update Available",
                    subtitle: "A newer version is in the Store.",
                    systemImage: "arrow.down.circle"
                ) {
                    Button(isUpdating ? String(localized: "Updating…") : String(localized: "Update")) {
                        update()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdating)
                }
            }

            if let packageURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([packageURL])
                } label: {
                    SettingsRow(title: "Show in Finder", systemImage: "folder") {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isConfirmingRemoval {
                HStack(alignment: .center, spacing: 12) {
                    SettingsRowLabel(
                        title: "Remove this extension?",
                        subtitle: "Its files and settings are deleted from this Mac.",
                        systemImage: "trash"
                    )
                    Spacer(minLength: 12)
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.15)) { isConfirmingRemoval = false }
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(isRemoving ? String(localized: "Removing…") : String(localized: "Remove")) {
                        remove(info)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isRemoving)
                }
                .padding(.vertical, 2)
            } else {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.15)) { isConfirmingRemoval = true }
                } label: {
                    SettingsRow(title: "Remove Extension…", systemImage: "trash") {
                        EmptyView()
                    }
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text(packageID)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Work

    private func loadManifest() async {
        let id = packageID
        let directory = Constants.extensionsDirectory
        let located = await Task.detached(priority: .utility) { () -> (ExtensionMetadata, URL)? in
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return nil }
            for item in items where !item.lastPathComponent.hasPrefix(".") {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      let manifestURL = ExtensionManifestStore.manifestFileURL(in: item),
                      let manifest = ExtensionManifestStore.readManifest(at: manifestURL),
                      manifest.identifier == id else { continue }
                return (manifest, item)
            }
            return nil
        }.value
        manifest = located?.0
        packageURL = located?.1
    }

    private func update() {
        isUpdating = true
        Task {
            do {
                try await updateManager.update(packageID: packageID)
            } catch {
                router.notifyError(
                    title: String(localized: "Update Failed"),
                    message: error.localizedDescription
                )
            }
            isUpdating = false
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        }
    }

    private func remove(_ info: InstalledExtensionInfo) {
        isRemoving = true
        let name = info.name
        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: info.uninstallActionID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                router.select(.customize)
                router.notify(SettingsNotice(
                    title: String(localized: "Extension Removed"),
                    message: String(localized: "\(name) was removed from this Mac."),
                    style: .info
                ))
            } catch {
                Log.extensions.error("Failed to uninstall extension '\(packageID, privacy: .public)': \(error.localizedDescription)")
                isRemoving = false
                isConfirmingRemoval = false
                router.notifyError(
                    title: String(localized: "Remove Failed"),
                    message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                )
            }
        }
    }
}
