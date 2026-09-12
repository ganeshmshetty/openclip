// ShortcutsPage.swift
// OpenClip
//
// Every action's hotkey and palette alias, in one table.
//
// Until now the only way to see or change an action's hotkey was to find its row in the Actions
// list, click its gear, and read the KEYBOARD card inside the floating editor — one action at a
// time, with no way to see what was already taken. Answering "what is ⌥⌘T bound to?" meant opening
// fifteen popovers.
//
// Every action's global shortcut on one categorized page, so bindings are set where they can be
// compared. The per-action page keeps its own copy of the same two fields — a binding is
// legitimately part of the action *and* part of the keyboard map, and System Settings duplicates
// settings across panes for the same reason.

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct ShortcutsPage: View {
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared
    @ObservedObject private var router = SettingsRouter.shared

    @State private var query = ""
    /// Alias drafts, so a half-typed alias does not get rejected on every keystroke.
    @State private var aliasDrafts: [String: String] = [:]
    @State private var aliasError: String?

    /// Bindable actions, grouped the way the Actions list groups them.
    private var sections: [(title: String, actions: [any Action])] {
        let bindable = coordinator.actions.filter { ActionIdentity.isBindable($0) }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = needle.isEmpty ? bindable : bindable.filter {
            title(for: $0).lowercased().contains(needle)
                || (bindingStore.alias(for: $0.id) ?? "").contains(needle)
        }

        var builtins: [any Action] = []
        var custom: [any Action] = []
        var extensions: [any Action] = []
        for action in filtered {
            switch action.chrome.source {
            case .builtin, .ai: builtins.append(action)
            case .custom: custom.append(action)
            case .extensionPkg: extensions.append(action)
            }
        }

        return [
            (String(localized: "Built-in"), builtins),
            (String(localized: "Custom Actions"), custom),
            (String(localized: "Extensions"), extensions),
        ].filter { !$0.actions.isEmpty }
    }

    private func title(for action: any Action) -> String {
        customizationManager.presented(action, surface: .table).title
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    // `prompt:` rather than the label: `labelsHidden()` is what stops a Form from
                    // promoting the label into its own column, and it takes the placeholder with it.
                    TextField("Search shortcuts", text: $query, prompt: Text("Search shortcuts"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("An alias jumps straight to an action when you type it in the palette. A hotkey runs it from anywhere.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(sections, id: \.title) { section in
                // No explicit dividers: a `Form` section already separates its rows, and adding
                // them made every row a double-height cell with a gap under it.
                Section(section.title) {
                    ForEach(section.actions, id: \.id) { action in
                        row(for: action)
                    }
                }
            }

            if let aliasError {
                Section {
                    Label(aliasError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(for action: any Action) -> some View {
        let presentation = customizationManager.presented(action, surface: .table)

        HStack(spacing: 10) {
            ActionIconView(icon: presentation.icon, size: 14)
                .frame(width: 18, height: 18)
                .foregroundColor(.secondary)

            // The name is the way into the action's own page: the shortcuts table is a map, and a
            // map should let you open what it points at.
            Button {
                router.push(.action(id: action.id))
            } label: {
                Text(presentation.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Configure Action")

            Spacer(minLength: 12)

            TextField("alias", text: aliasBinding(for: action.id), prompt: Text("alias"))
                .textFieldStyle(.roundedBorder)
                // A Form lays a cell out as label + control, which turned each field's placeholder
                // into a column of its own.
                .labelsHidden()
                .frame(width: 88)
                .accessibilityLabel(String(localized: "Alias for \(presentation.title)"))

            KeyboardShortcuts.Recorder(for: .actionHotkey(action.id))
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
                    aliasError = nil
                case .invalid:
                    aliasError = String(localized: "Aliases can only contain letters and numbers.")
                case .collision:
                    aliasError = String(localized: "That alias is already used.")
                }
            }
        )
    }
}
