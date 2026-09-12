// ExtensionPackagePage.swift
// OpenClip
//
// One installed extension's settings page: a hero saying what it is and who made it, the actions
// it adds and the way into each one's settings — the same page whether the package groups five
// commands behind one icon or contributes a single command. Its command table is
// `ActionSettingsRow`, the same rows the Shortcuts page is made of. Whether it is on, and what can be done to it as a
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
    /// Why an alias typed in the table below was refused.
    @State private var aliasError: String?

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

    /// The page's sections, in the order they appear. Only the ones with something to show are
    /// rendered — an empty `Section` still draws its card, which is how a one-command extension
    /// (no group, so no name-and-icon row) ended up with a blank card at the foot of the page.
    private enum PageSection {
        case gate
        case update
        case actions
        case naming
    }

    private func sections(for info: InstalledExtensionInfo) -> [PageSection] {
        var sections: [PageSection] = []
        if info.gatedReason != nil { sections.append(.gate) }
        if updateManager.updatablePackageIDs.contains(packageID) { sections.append(.update) }
        if !info.commands.isEmpty { sections.append(.actions) }
        if info.containerActionID != nil { sections.append(.naming) }
        return sections
    }

    private func page(for info: InstalledExtensionInfo) -> some View {
        let sections = sections(for: info)
        // The identifier rides whichever section ends the page, so it is always the last thing
        // and never needs a card of its own.
        let last = sections.last

        return Form {
            // The hero rides a section header rather than sitting above the form: a header
            // scrolls with the content and draws no card, where a view above the form stayed
            // pinned under the toolbar however far the page was scrolled.
            Section {
                EmptyView()
            } header: {
                SettingsHeroHeader(
                    glyph: .icon(info.icon, tint: ExtensionTint.color(for: packageID)),
                    title: info.name,
                    subtitle: manifest?.localizedDescription?.resolve() ?? manifest?.description,
                    footnote: byline
                )
            }

        if sections.contains(.gate), let reason = info.gatedReason,
               let text = extensionGateDescription(for: reason) {
                Section {
                    Label {
                        Text(text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    identifierFooter(if: last == .gate)
                }
            }

            if sections.contains(.update) {
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
                } footer: {
                    identifierFooter(if: last == .update)
                }
            }

            if sections.contains(.actions) {
                Section {
                    ForEach(info.commands, id: \.id) { action in
                        ActionSettingsRow(
                            action: action,
                            disabledActionIDs: $disabledActionIDs,
                            disabledPackages: $disabledPackages,
                            onAliasMessage: { message in
                                withAnimation(.easeInOut(duration: 0.18)) { aliasError = message }
                            }
                        )
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        if let aliasError {
                            SettingsInlineError(message: aliasError)
                        }

                        Text(info.commands.count == 1
                             ? "Turn the action off to hide it from the popup bar. Open it to change its name, icon, shortcut and options."
                             : "Turn an action off to hide it from the popup bar. Open one to change its name, icon, shortcut and options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        identifierFooter(if: last == .actions)
                    }
                }
            }

            if sections.contains(.naming), let containerID = info.containerActionID {
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
                    identifierFooter(if: last == .naming)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The package identifier, quiet and selectable: the one thing on the page a bug report needs.
    @ViewBuilder
    private func identifierFooter(if shouldShow: Bool) -> some View {
        if shouldShow {
            Text(packageID)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
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
