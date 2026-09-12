// ExtensionPackagePage.swift
// OpenClip
//
// One installed extension's settings page: a hero saying what it is and who made it, the actions
// it adds and the way into each one's settings. Whether it is on, and what can be done to it as a
// whole — view its README, show its folder, uninstall it — live in the toolbar beside the back and
// forward arrows, because they belong to the extension rather than to any row of the page.
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
    /// Manifest, folder and README, read by the window (which also needs them for the toolbar's
    /// ellipsis menu). `nil` until the read lands, or for a standalone script extension.
    let details: ExtensionPackageDetails?
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    @State private var isUpdating = false

    init(
        packageID: String,
        details: ExtensionPackageDetails?,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>
    ) {
        self.packageID = packageID
        self.details = details
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    private var info: InstalledExtensionInfo? {
        InstalledExtensionInfo.info(for: packageID, in: coordinator.actions)
    }

    private var manifest: ExtensionMetadata? { details?.manifest }

    var body: some View {
        Group {
            if let info {
                page(for: info)
            } else {
                // The package went away while its page was open (uninstalled from the Store, or
                // its folder was deleted). Show the list rather than an empty pane.
                Color.clear.onAppear { router.select(.customize) }
            }
        }
    }

    private func page(for info: InstalledExtensionInfo) -> some View {
        VStack(spacing: 0) {
            SettingsHeroHeader(
                glyph: .icon(info.icon, tint: ExtensionTint.color(for: packageID)),
                title: info.name,
                subtitle: manifest?.localizedDescription?.resolve() ?? manifest?.description,
                footnote: byline
            )

            Form {
                if let reason = info.gatedReason, let text = extensionGateDescription(for: reason) {
                    Section {
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

                if updateManager.updatablePackageIDs.contains(packageID) {
                    Section {
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
                }

                actionsSection(info)

                if let containerID = info.containerActionID {
                    Section {
                        SettingsDisclosureRow {
                            router.push(.action(id: containerID))
                        } content: {
                            SettingsRowLabel(
                                title: "Name and Icon in Popup Bar",
                                subtitle: "Rename the group or change the icon its actions sit behind.",
                                systemImage: "square.grid.2x2"
                            )
                        }
                    } footer: {
                        identifierFooter
                    }
                } else {
                    Section {
                        EmptyView()
                    } footer: {
                        identifierFooter
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// The package identifier, quiet and selectable: the one thing on the page a bug report needs.
    private var identifierFooter: some View {
        Text(packageID)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .center)
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

    // MARK: - Work

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
}
