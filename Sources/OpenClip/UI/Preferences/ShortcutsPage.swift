// ShortcutsPage.swift
// OpenClip
//
// The Shortcuts page: per-action hotkeys and palette aliases.
// Styled with inset SettingsCards.

import SwiftUI
import Core

@MainActor
struct ShortcutsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    @Binding var query: String

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared

    @State private var aliasError: String?

    init(
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        query: Binding<String>
    ) {
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
        _query = query
    }

    private struct ShortcutGroup: Identifiable {
        let id: String
        let title: String
        let actions: [any Action]
    }

    private var groups: [ShortcutGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ action: any Action) -> Bool {
            guard !needle.isEmpty else { return true }
            if title(for: action).lowercased().contains(needle) { return true }
            if (bindingStore.alias(for: action.id) ?? "").lowercased().contains(needle) { return true }
            return action.keywords.contains { $0.lowercased().contains(needle) }
        }

        var extensionGroups: [ShortcutGroup] = []
        var extensionActionIDs = Set<String>()
        for info in InstalledExtensionInfo.all(from: coordinator.actions) {
            extensionActionIDs.formUnion(info.commands.map(\.id))
            let commands = info.commands.filter { ActionIdentity.isBindable($0) && matches($0) }
            if !commands.isEmpty {
                extensionGroups.append(ShortcutGroup(id: "extension:\(info.packageID)", title: info.name, actions: commands))
            }
        }

        var builtins: [any Action] = []
        var aiPresets: [any Action] = []
        var custom: [any Action] = []
        for action in coordinator.actions where ActionIdentity.isBindable(action) && !extensionActionIDs.contains(action.id) {
            guard matches(action) else { continue }
            if ActionIdentity.isAIPreset(action) {
                aiPresets.append(action)
            } else if SettingsDestination.isCustomAction(action) {
                custom.append(action)
            } else if ActionIdentity.isBuiltin(action) {
                builtins.append(action)
            }
        }

        return [
            ShortcutGroup(id: "builtin", title: String(localized: "Built-in"), actions: builtins),
            ShortcutGroup(id: "ai", title: String(localized: "AI"), actions: aiPresets),
            ShortcutGroup(id: "custom", title: String(localized: "Custom Actions"), actions: custom),
        ].filter { !$0.actions.isEmpty } + extensionGroups
    }

    private func title(for action: any Action) -> String {
        customizationManager.presented(action, surface: .table).title
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groups) { group in
                            SettingsCard(LocalizedStringKey(group.title)) {
                                ForEach(Array(group.actions.enumerated()), id: \.element.id) { index, action in
                                    if index > 0 {
                                        SettingsDivider(insetLeading: 16)
                                    }
                                    row(for: action)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                }
                            }
                        }

                        Text("Switch an action off to hide it from the popup bar and the palette. An alias jumps straight to an action when you type it in the palette; a hotkey runs it from anywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            NativeSearchField(
                text: $query,
                placeholder: String(localized: "Search shortcuts"),
                controlSize: .regular
            )
            .frame(height: 24)

            if let aliasError {
                SettingsInlineError(message: aliasError)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func row(for action: any Action) -> some View {
        ActionSettingsRow(
            action: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            onAliasMessage: { message in
                withAnimation(.easeInOut(duration: 0.18)) { aliasError = message }
            }
        )
    }
}
