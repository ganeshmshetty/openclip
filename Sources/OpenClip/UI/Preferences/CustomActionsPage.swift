// CustomActionsPage.swift
// OpenClip
//
// The user's own actions — Open URL, Text Snippet, Shell Script — as one sidebar page, the way
// Raycast keeps Quicklinks and Script Commands together: a hero, then each action in the same
// `ActionSettingsRow` table the Shortcuts page and an extension's page use, and the way to add
// another. Duplicating or deleting one is done from
// its own page's toolbar menu.

import SwiftUI
import Core

@MainActor
struct CustomActionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var router = SettingsRouter.shared
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

            Section {
                if customActions.isEmpty {
                    Text("No custom actions yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
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
                    }
                }

                SettingsDisclosureRow {
                    router.push(.newCustomAction)
                } content: {
                    Label("Add Custom Action", systemImage: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Text("Actions")
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    if let aliasError {
                        SettingsInlineError(message: aliasError)
                    }

                    Text("Open an action to change its name, icon, shortcut or what it does, or to delete it. Use Customize to place it in the popup bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func kindDescription(_ action: any Action) -> String {
        guard let custom = action as? CustomAction else { return String(localized: "Custom Action") }
        switch custom.type {
        case .openURL: return String(localized: "Open URL")
        case .textSnippet: return String(localized: "Text Snippet")
        case .shellScript: return String(localized: "Shell Script")
        }
    }
}
