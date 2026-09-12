// ShortcutsPage.swift
// OpenClip
//
// Every action's switch, alias and hotkey in one table, grouped the way System Settings groups
// keyboard shortcuts by app: built-ins, AI prompts, the user's custom actions, then one group per
// installed extension. It is the page for questions like "what is ⌥⌘T bound to?" and "which of
// these are actually on?", and every row is one click from the action's own page.
//
// The switch and the alias/hotkey pair also appear on each action's page; a binding is
// legitimately part of the action *and* part of the keyboard map, and System Settings duplicates
// settings across panes for the same reason.

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct ShortcutsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var query = ""
    /// Alias drafts, so a half-typed alias does not get rejected on every keystroke.
    @State private var aliasDrafts: [String: String] = [:]
    @State private var aliasError: String?

    init(disabledActionIDs: Binding<Set<String>>, disabledPackages: Binding<Set<String>>) {
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    private struct ShortcutGroup: Identifiable {
        let id: String
        let title: String
        let actions: [any Action]
    }

    /// Bindable actions that answer the search, grouped by where they come from.
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
                Form {
                    ForEach(groups) { group in
                        // No explicit dividers: a `Form` section already separates its rows, and
                        // adding them made every row a double-height cell with a gap under it.
                        Section(group.title) {
                            ForEach(group.actions, id: \.id) { action in
                                row(for: action)
                            }
                        }
                    }

                    Section {
                        EmptyView()
                    } footer: {
                        Text("Switch an action off to hide it from the popup bar and the palette. An alias jumps straight to an action when you type it in the palette; a hotkey runs it from anywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func row(for action: any Action) -> some View {
        let presentation = customizationManager.presented(action, surface: .table)
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages
        )

        HStack(spacing: 10) {
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentation.title)"))

            // The name is the way into the action's own page: the shortcuts table is a map, and a
            // map should let you open what it points at.
            Button {
                SettingsDestination.open(action)
            } label: {
                HStack(spacing: 8) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                    Text(presentation.title)
                        .font(.system(size: 13))
                        .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure Action")

            TextField("alias", text: aliasBinding(for: action.id), prompt: Text("alias"))
                .textFieldStyle(.roundedBorder)
                // A Form lays a cell out as label + control, which turned each field's placeholder
                // into a column of its own.
                .labelsHidden()
                .frame(width: 88)
                .accessibilityLabel(String(localized: "Alias for \(presentation.title)"))

            KeyboardShortcuts.Recorder(for: .actionHotkey(action.id))

            Button {
                SettingsDestination.open(action)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure Action")
            .accessibilityLabel(String(localized: "Configure \(presentation.title)"))
        }
        .padding(.vertical, 3)
    }

    /// Writes through to `ActionBindingStore`, surfacing the same collision message the per-action
    /// editor shows rather than silently dropping the alias.
    private func aliasBinding(for actionID: String) -> Binding<String> {
        Binding(
            get: { aliasDrafts[actionID] ?? bindingStore.alias(for: actionID) ?? "" },
            set: { newValue in
                aliasDrafts[actionID] = newValue
                switch bindingStore.setAlias(newValue, for: actionID) {
                case .accepted, .cleared:
                    withAnimation(.easeInOut(duration: 0.18)) { aliasError = nil }
                case .invalid:
                    withAnimation(.easeInOut(duration: 0.18)) {
                        aliasError = String(localized: "Aliases can only contain letters and numbers.")
                    }
                case .collision:
                    withAnimation(.easeInOut(duration: 0.18)) {
                        aliasError = String(localized: "That alias is already used.")
                    }
                }
            }
        )
    }
}
