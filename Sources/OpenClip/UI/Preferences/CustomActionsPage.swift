// CustomActionsPage.swift
// OpenClip
//
// The user's own actions — Open URL, Text Snippet, Shell Script — as one sidebar page:
// a hero header, quick-start cards for creating new actions, and each action in the same
// ActionSettingsRow table the Shortcuts page and an extension's page use.

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct CustomActionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    @State private var hoveredKind: String? = nil
    /// Why an alias typed in the table below was refused.
    @State private var aliasError: String?

    init(disabledActionIDs: Binding<Set<String>>, disabledPackages: Binding<Set<String>>) {
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    private var customActions: [any Action] {
        var seen = Set<String>()
        return coordinator.actions.filter { action in
            SettingsDestination.isCustomAction(action) && seen.insert(action.id).inserted
        }
    }

    var body: some View {
        Form {
            // A section header rather than a view above the form, so the hero scrolls away with
            // the rest of the page instead of staying pinned under the toolbar.
            Section {
                EmptyView()
            } header: {
                SettingsHeroHeader(
                    glyph: .symbol(SettingsPage.customActions.systemImage, tint: SettingsPage.customActions.tint),
                    title: String(localized: "Custom Actions"),
                    subtitle: String(localized: "Actions you made yourself: open a URL with the selection, paste a snippet built from it, or run a shell script on it.")
                )
            }

            if !customActions.isEmpty {
                Section {
                    ForEach(customActions, id: \.id) { action in
                        ActionSettingsRow(
                            action: action,
                            disabledActionIDs: $disabledActionIDs,
                            disabledPackages: $disabledPackages,
                            subtitle: kindDescription(action),
                            onAliasMessage: { message in
                                withAnimation(.easeInOut(duration: 0.18)) { aliasError = message }
                            }
                        )
                        .contextMenu {
                            Button(String(localized: "Configure…")) {
                                SettingsDestination.open(action)
                            }
                            if ActionIdentity.canDuplicate(action) {
                                Button(String(localized: "Duplicate")) {
                                    Task {
                                        _ = await ActionDuplicator.duplicate(actionID: action.id)
                                    }
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                confirmDelete(action)
                            } label: {
                                Text("Delete Action…")
                            }
                        }
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let aliasError {
                            SettingsInlineError(message: aliasError)
                        }

                        Text("Open an action to change its name, icon, shortcut or what it does, or to delete it. Use Actions to place it in the popup bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                quickCreateRow(
                    kind: "url",
                    title: "Open URL",
                    subtitle: "Open a web URL or search engine query using the selected text",
                    systemImage: "safari.fill",
                    tint: .blue
                )

                quickCreateRow(
                    kind: "snippet",
                    title: "Text Snippet",
                    subtitle: "Transform or format the selection using template placeholders",
                    systemImage: "text.quote",
                    tint: .green
                )

                quickCreateRow(
                    kind: "shell",
                    title: "Shell Script",
                    subtitle: "Execute a bash or zsh script with the selection in OPENCLIP_TEXT",
                    systemImage: "terminal.fill",
                    tint: .purple
                )
            } header: {
                Text(customActions.isEmpty ? "Get Started" : "Create New Action")
            } footer: {
                if customActions.isEmpty {
                    Text("Custom actions appear in your popup bar and palette. You can trigger them anytime with hotkeys or aliases.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func quickCreateRow(
        kind: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        tint: Color
    ) -> some View {
        Button {
            router.push(.newCustomAction(kind: kind))
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(systemImage: systemImage, tint: tint, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Create")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(tint.opacity(hoveredKind == kind ? 0.22 : 0.12))
                )
                .scaleEffect(hoveredKind == kind ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: hoveredKind == kind)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredKind = isHovered ? kind : nil
        }
    }

    private func kindDescription(_ action: any Action) -> String {
        guard let custom = action as? CustomAction else { return String(localized: "Custom Action") }
        switch custom.type {
        case .openURL: return String(localized: "Open URL")
        case .textSnippet: return String(localized: "Text Snippet")
        case .shellScript: return String(localized: "Shell Script")
        }
    }

    private func confirmDelete(_ action: any Action) {
        let id = action.id
        router.confirmDestructive(
            title: String(localized: "Delete?"),
            message: "",
            confirmTitle: String(localized: "Delete")
        ) {
            KeyboardShortcuts.reset(.actionHotkey(id))
            coordinator.deleteCustomAction(actionID: id)
            ActionCustomizationManager.shared.resetOverride(for: id)
            router.clearConfigurationRequest(for: id)
            Task {
                do {
                    try await ExtensionManager.shared.uninstallExtension(actionID: id)
                    NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                } catch {
                    let nsError = error as NSError
                    if !(nsError.domain == "ExtensionManager" && nsError.code == 404) {
                        Log.extensions.error("Failed to remove custom action on disk '\(id, privacy: .public)': \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
