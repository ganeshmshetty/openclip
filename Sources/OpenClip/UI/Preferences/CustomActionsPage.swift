// CustomActionsPage.swift
// OpenClip
//
// The user's own actions — Open URL, Text Snippet, Shell Script — as one sidebar page, the way
// Raycast keeps Quicklinks and Script Commands together: each with its switch and a way into its
// editor, and the way to add another. Deleting one is done on its page.

import SwiftUI
import Core

@MainActor
struct CustomActionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var router = SettingsRouter.shared

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
                HStack(alignment: .center, spacing: 14) {
                    SettingsIconTile(systemImage: SettingsPage.customActions.systemImage, tint: SettingsPage.customActions.tint, size: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custom Actions")
                            .font(.title3.weight(.semibold))
                        Text("Actions you made yourself: open a URL with the selection, paste a snippet built from it, or run a shell script on it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.vertical, 6)
            }

            Section {
                if customActions.isEmpty {
                    Text("No custom actions yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(customActions, id: \.id) { action in
                        row(action)
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
                Text("Open an action to change its name, icon, shortcut or what it does, or to delete it. Use Customize to place it in the popup bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ action: any Action) -> some View {
        let presentation = customizationManager.presented(action, surface: .table)

        return HStack(spacing: 10) {
            Button {
                router.push(.action(id: action.id))
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .lineLimit(1)
                        Text(kindDescription(action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

    private func kindDescription(_ action: any Action) -> String {
        guard let custom = action as? CustomAction else { return String(localized: "Custom Action") }
        switch custom.type {
        case .openURL: return String(localized: "Open URL")
        case .textSnippet: return String(localized: "Text Snippet")
        case .shellScript: return String(localized: "Shell Script")
        }
    }
}
