// ActionSettingsRow.swift
// OpenClip
//
// One action as a row of a settings table: whether it is on, its name — which opens its page —
// its palette alias, its hotkey, and the chevron that says the name is a way in.
//
// Every list of actions in the window is this row: the Shortcuts table, the commands on an
// extension's page, and the user's Custom Actions. They were three hand-written tables that drifted
// apart — the same action showed a switch in one, an alias in another, and the columns never lined
// up — so they are one component now and line up by construction.

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct ActionSettingsRow: View {
    let action: any Action
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// A second line under the name, where a list has something worth saying about each row (the
    /// kind of a custom action). Nil everywhere else, which is what keeps the rows one height.
    var subtitle: String?
    /// Called with why an alias was rejected, and with nil once one is accepted. Each page puts
    /// the message where it has room for it.
    var onAliasMessage: (String?) -> Void

    init(
        action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        subtitle: String? = nil,
        onAliasMessage: @escaping (String?) -> Void = { _ in }
    ) {
        self.action = action
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
        self.subtitle = subtitle
        self.onAliasMessage = onAliasMessage
    }

    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared

    /// The half-typed alias, so it is not rejected on the keystroke that would have completed it.
    @State private var aliasDraft: String?

    /// Width of the alias field: room for the two or three letters an alias is meant to be.
    private static let aliasWidth: CGFloat = 88

    var body: some View {
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

            // The name is the way into the action's page: a table of actions should let you open
            // what it points at.
            Button {
                SettingsDestination.open(action)
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.system(size: 13))
                            .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure Action")

            if ActionIdentity.isBindable(action) {
                TextField("alias", text: aliasBinding, prompt: Text("alias"))
                    .textFieldStyle(.roundedBorder)
                    // A Form lays a cell out as label + control, which turned each field's
                    // placeholder into a column of its own.
                    .labelsHidden()
                    .frame(width: Self.aliasWidth)
                    .accessibilityLabel(String(localized: "Alias for \(presentation.title)"))

                KeyboardShortcuts.Recorder(for: .actionHotkey(action.id))
            }

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
            .accessibilityLabel(String(localized: "Configure \(presentation.title)"))
        }
        .padding(.vertical, 3)
    }

    /// Writes through to `ActionBindingStore`, reporting the same refusal the action's own editor
    /// gives rather than silently dropping what was typed.
    private var aliasBinding: Binding<String> {
        Binding(
            get: { aliasDraft ?? bindingStore.alias(for: action.id) ?? "" },
            set: { newValue in
                aliasDraft = newValue
                switch bindingStore.setAlias(newValue, for: action.id) {
                case .accepted, .cleared:
                    onAliasMessage(nil)
                case .invalid:
                    onAliasMessage(String(localized: "Aliases can only contain letters and numbers."))
                case .collision:
                    onAliasMessage(String(localized: "That alias is already used."))
                }
            }
        )
    }
}
