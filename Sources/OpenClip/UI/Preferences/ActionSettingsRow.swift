// ActionSettingsRow.swift
// OpenClip
//
// One action as a settings-table row: enable switch, name, alias, hotkey, chevron. Shared by every
// action list so their columns line up.

import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct ActionSettingsRow: View {
    let action: any Action
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// Second line under the name. Nil keeps rows one height.
    var subtitle: String?
    /// Receives the alias rejection message, or nil once accepted.
    var onAliasMessage: (String?) -> Void
    private let coordinator: ActionCoordinator

    init(
        action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        coordinator: ActionCoordinator = .shared,
        subtitle: String? = nil,
        onAliasMessage: @escaping (String?) -> Void = { _ in }
    ) {
        self.action = action
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
        self.coordinator = coordinator
        self.subtitle = subtitle
        self.onAliasMessage = onAliasMessage
    }

    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared

    /// Half-typed alias; avoids rejecting it mid-typing.
    @State private var aliasDraft: String?

    /// Fits two or three letters.
    private static let aliasWidth: CGFloat = 88

    var body: some View {
        let presentation = customizationManager.presented(action, surface: .table)
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            coordinator: coordinator
        )
        let parentIsDisabled = coordinator.isDisabledByParentGroup(
            action, disabledActionIDs: disabledActionIDs, disabledPackages: disabledPackages
        )

        HStack(spacing: 10) {
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentation.title)"))
                .disabled(parentIsDisabled)

            Button {
                SettingsDestination.open(action)
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                        .opacity(parentIsDisabled ? 0.45 : 1)

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
                    // Inside a Form the placeholder would become a column of its own.
                    .labelsHidden()
                    .frame(width: Self.aliasWidth)
                    .accessibilityLabel(String(localized: "Alias for \(presentation.title)"))

                Shortcut(for: .actionHotkey(action.id))
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

    /// Writes through to `ActionBindingStore`, reporting refusals instead of dropping input.
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
