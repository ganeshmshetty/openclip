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
            Section {
                HStack(spacing: 14) {
                    let size: CGFloat = 42
                    let radius = SettingsDesignTokens.iconTileRadius(for: size)
                    let squircle = RoundedRectangle(cornerRadius: radius, style: .continuous)

                    ZStack {
                        squircle
                            .fill(SettingsTint.neutral)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Custom Actions"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .lineLimit(1)

                        Text(String(localized: "Create your own quick actions using URL templates, snippet placeholders, or shell scripts."))
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesignTokens.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.vertical, 4)
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

                        Text("Open an action to customize its name, icon, shortcut, or behavior. Configure its appearance in the Actions tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                quickCreateRow(
                    kind: "url",
                    title: "Open URL",
                    subtitle: "Search the web or open query URLs with selected text",
                    systemImage: "safari.fill"
                )

                quickCreateRow(
                    kind: "snippet",
                    title: "Text Snippet",
                    subtitle: "Expand reusable text templates with dynamic placeholders",
                    systemImage: "text.quote"
                )

                quickCreateRow(
                    kind: "shell",
                    title: "Shell Script",
                    subtitle: "Automate tasks by running custom bash or zsh scripts",
                    systemImage: "terminal.fill"
                )
            } header: {
                Text(customActions.isEmpty ? "Get Started" : "Create New Action")
            } footer: {
                if customActions.isEmpty {
                    Text("Custom actions appear in your popup bar and search palette. Assign global hotkeys or search aliases to trigger them anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func quickCreateRow(
        kind: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Button {
            router.push(.newCustomAction(kind: kind))
        } label: {
            HStack(spacing: 12) {
                let tint = SettingsDesignTokens.iconTileColor(forSystemImage: systemImage)
                SettingsIconTile(systemImage: systemImage, tint: tint, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.primaryText)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsDesignTokens.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Create")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(SettingsDesignTokens.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hoveredKind == kind ? 0.10 : 0.05))
                )
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
