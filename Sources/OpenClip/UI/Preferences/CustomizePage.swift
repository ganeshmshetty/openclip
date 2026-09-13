// CustomizePage.swift
// OpenClip
//
// The Customize page: the popup bar's layout, action enablement, palette aliases, and hotkeys.
// One reorderable outline of everything the bar shows — drag to change the order, drag onto a group
// to add to it, select several rows and make a group of them. Each row also hosts an enable toggle,
// alias text field, and hotkey recorder.

import SwiftUI
import UniformTypeIdentifiers
import Core
import KeyboardShortcuts

@MainActor
struct CustomizePage: View {
    @Binding var selectedRowIDs: Set<String>
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

    @State private var query = ""
    @State private var aliasError: String?

    init(
        selectedRowIDs: Binding<Set<String>>,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>
    ) {
        _selectedRowIDs = selectedRowIDs
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    /// Eligible candidate action IDs for custom grouping. Only top-level standalone actions
    /// (not AI presets, not AI launcher, not group parents, not extension sub-actions,
    /// and not existing custom group members) can be selected for a new group.
    static func groupCandidates(selectedRowIDs: Set<String>, coordinator: ActionCoordinator) -> [String] {
        let customGroupMemberIDs = Set(coordinator.actionGroupDefs.flatMap(\.memberActionIDs))

        return coordinator.actions.compactMap { action in
            guard selectedRowIDs.contains(action.id) else { return nil }
            guard coordinator.isEligibleForGrouping(actionID: action.id) else { return nil }
            if customGroupMemberIDs.contains(action.id) { return nil }
            return action.id
        }
    }

    private var hasNoMatches: Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        let matchingActions = coordinator.actions.contains { action in
            if customizationManager.presented(action, surface: .table).title.lowercased().contains(needle) { return true }
            if (ActionBindingStore.shared.alias(for: action.id) ?? "").lowercased().contains(needle) { return true }
            return action.keywords.contains { $0.lowercased().contains(needle) }
        }
        if matchingActions { return false }
        let matchingGroups = coordinator.actionGroupDefs.contains { $0.title.lowercased().contains(needle) }
        return !matchingGroups
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ZStack {
                ActionsOutlineView(
                    coordinator: coordinator,
                    customizationManager: customizationManager,
                    searchQuery: query,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages,
                    selectedRowIDs: $selectedRowIDs,
                    onAliasMessage: { message in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            aliasError = message
                        }
                    },
                    onEditGroup: { groupID in
                        SettingsRouter.shared.push(.action(id: groupID))
                    },
                    onCreateGroupFromSelection: {
                        SettingsRouter.shared.push(.newGroup(
                            memberIDs: Self.groupCandidates(selectedRowIDs: selectedRowIDs, coordinator: coordinator)
                        ))
                    },
                    onOpenNode: { node in
                        switch node.kind {
                        case .packageHeader(let packageID, _, _):
                            SettingsRouter.shared.show(path: SettingsDestination.path(forPackage: packageID))
                        default:
                            if let action = node.action {
                                SettingsDestination.open(action)
                            }
                        }
                    }
                )

                if hasNoMatches {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerHint
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeSearchField(
                text: $query,
                placeholder: String(localized: "Search actions, shortcuts, or aliases"),
                controlSize: .regular
            )
            .frame(height: 24)

            if let aliasError {
                SettingsInlineError(message: aliasError)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .foregroundStyle(.tertiary)
            Text("Drag to reorder the popup bar or group actions. Turn off an action to hide it. An alias or hotkey triggers an action anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Rows

/// One action in the Customize list: icon, title, alias, hotkey recorder, enable toggle, and delete.
@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    var onAliasMessage: (String?) -> Void

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared
    @State private var aliasDraft: String?

    private static let aliasWidth: CGFloat = 88

    private var isDeletable: Bool {
        // Custom group
        if coordinator.actionGroupDefs.contains(where: { $0.id == action.id }) {
            return true
        }
        // Custom AI Preset
        if ActionIdentity.isAIPreset(action) {
            if let preset = AIServiceManager.shared.preset(forActionID: action.id) {
                return preset.id.hasPrefix("custom_")
            }
            return false
        }
        // Custom action
        if SettingsDestination.isCustomAction(action) {
            return true
        }
        // Top-level extension action or extension group parent
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           !InstalledExtensionInfo.isCustomPackage(packageID) {
            let isSubAction = action.id.contains(".") && action.chrome.popupBehavior != .showSubActions
            return !isSubAction
        }
        return false
    }

    var body: some View {
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages
        )

        HStack(alignment: .center, spacing: 10) {
            ActionIconView(icon: presentationModel.icon, size: 16)
                .frame(width: 22, height: 22, alignment: .center)
                .foregroundStyle(.secondary)

            Text(presentationModel.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                .lineLimit(1)

            if let gated = action as? GatedExtensionAction, let tooltip = extensionGateDescription(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer(minLength: 8)

            if ActionIdentity.isBindable(action) {
                TextField("alias", text: aliasBinding, prompt: Text("alias"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: Self.aliasWidth)
                    .accessibilityLabel(String(localized: "Alias for \(presentationModel.title)"))

                KeyboardShortcuts.Recorder(for: .actionHotkey(action.id))
                    .controlSize(.small)
            }

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentationModel.title)"))

            if isDeletable {
                Button {
                    confirmDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Delete / Uninstall"))
            } else {
                Color.clear
                    .frame(width: 20, height: 20)
            }

            Button {
                SettingsDestination.open(action)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Configure \(presentationModel.title)"))
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .id(action.id)
    }

    private func confirmDelete() {
        let title = presentationModel.title

        // 1. Custom Group
        if coordinator.actionGroupDefs.contains(where: { $0.id == action.id }) {
            SettingsRouter.shared.confirmDestructive(
                title: String(localized: "Delete Group \(title)?"),
                message: String(localized: "Actions inside this group will return to the top level."),
                confirmTitle: String(localized: "Delete")
            ) {
                coordinator.ungroup(groupID: action.id)
            }
            return
        }

        // 2. Custom AI Preset
        if ActionIdentity.isAIPreset(action),
           let preset = AIServiceManager.shared.preset(forActionID: action.id) {
            SettingsRouter.shared.confirmDestructive(
                title: String(localized: "Delete \(title)?"),
                message: String(localized: "This AI action will be permanently removed."),
                confirmTitle: String(localized: "Delete")
            ) {
                var list = AIServiceManager.shared.presets
                list.removeAll(where: { $0.id == preset.id })
                AIServiceManager.shared.presets = list
            }
            return
        }

        // 3. Custom Action
        if case .custom = action.chrome.source {
            SettingsRouter.shared.confirmDestructive(
                title: String(localized: "Delete \(title)?"),
                message: String(localized: "The action is removed from the popup bar and the palette."),
                confirmTitle: String(localized: "Delete")
            ) {
                coordinator.deleteCustomAction(actionID: action.id)
                customizationManager.resetOverride(for: action.id)
            }
            return
        }

        // 4. Installed Extension
        if let packageID = ActionIdentity.extensionPackageID(of: action) {
            let info = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions)
            let extName = info?.name ?? title
            let uninstallID = info?.uninstallActionID ?? action.id
            SettingsRouter.shared.confirmDestructive(
                title: String(localized: "Uninstall \(extName)?"),
                message: String(localized: "Its files and settings are deleted from this Mac."),
                confirmTitle: String(localized: "Uninstall")
            ) {
                Task {
                    do {
                        try await ExtensionManager.shared.uninstallExtension(actionID: uninstallID)
                        customizationManager.resetOverride(for: action.id)
                        NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                        SettingsRouter.shared.notify(SettingsNotice(
                            title: String(localized: "Extension Removed"),
                            message: String(localized: "\(extName) was removed from this Mac."),
                            style: .info
                        ))
                    } catch {
                        SettingsRouter.shared.notifyError(
                            title: String(localized: "Remove Failed"),
                            message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                        )
                    }
                }
            }
            return
        }
    }

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

/// The header row of a multi-action package that is not a group: label and package enable toggle.
@MainActor
struct PackageHeaderRowView: View {
    let title: String
    let packageID: String
    let gatedReason: ExtensionGateReason?
    @Binding var disabledPackages: Set<String>

    var body: some View {
        let isEnabled = ActionEnablement.packageBinding(
            packageID: packageID,
            gatedReason: gatedReason,
            disabledPackages: $disabledPackages
        )

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22, alignment: .center)

            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.secondary)

            if let gatedReason, let tooltip = extensionGateDescription(for: gatedReason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(title)"))

            Button {
                confirmUninstall()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Uninstall Extension"))

            Color.clear
                .frame(width: 16, height: 16)
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
    }

    private func confirmUninstall() {
        SettingsRouter.shared.confirmDestructive(
            title: String(localized: "Uninstall \(title)?"),
            message: String(localized: "Its files and settings are deleted from this Mac."),
            confirmTitle: String(localized: "Uninstall")
        ) {
            Task {
                do {
                    let actionID = InstalledExtensionInfo.info(for: packageID, in: ActionCoordinator.shared.actions)?.uninstallActionID ?? packageID
                    try await ExtensionManager.shared.uninstallExtension(actionID: actionID)
                    NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                    SettingsRouter.shared.notify(SettingsNotice(
                        title: String(localized: "Extension Removed"),
                        message: String(localized: "\(title) was removed from this Mac."),
                        style: .info
                    ))
                } catch {
                    SettingsRouter.shared.notifyError(
                        title: String(localized: "Remove Failed"),
                        message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                    )
                }
            }
        }
    }
}

/// Why a package is gated, as a tooltip on a red dot.
private struct GateInfoIcon: View {
    let tooltip: String

    var body: some View {
        Image(systemName: "info.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.red)
            .help(tooltip)
            .accessibilityLabel(tooltip)
    }
}
