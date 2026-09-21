// CustomizePage.swift
// OpenClip
//
// The Customize page: the popup bar's layout and action enablement.
// One reorderable outline of everything the bar shows — drag to change the order, drag onto a group
// to add to it, select several rows and make a group of them. Each row carries an enable toggle and a
// chevron to its own page, where its alias, hotkey, and delete live. The search field lives in the
// window toolbar, like the Store's, so the list itself is just the list.

import SwiftUI
import UniformTypeIdentifiers
import Core

@MainActor
struct CustomizePage: View {
    @Binding var selectedRowIDs: Set<String>
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// The toolbar's search field, routed here by the window while this page is on screen.
    @Binding var query: String

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

    @State private var isShowingHelp = false

    init(
        selectedRowIDs: Binding<Set<String>>,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        query: Binding<String>
    ) {
        _selectedRowIDs = selectedRowIDs
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
        _query = query
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
        ZStack {
            ActionsOutlineView(
                coordinator: coordinator,
                customizationManager: customizationManager,
                searchQuery: query,
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages,
                selectedRowIDs: $selectedRowIDs,
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
                // No background: the outline is empty, so the pane shows through and the empty
                // state reads as part of the pane instead of a mismatched rectangle.
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            helpButton
        }
    }

    /// The page's instructions, behind the floating help button the pane keeps in its corner —
    /// the same affordance System Settings uses, so the list itself stays uncluttered.
    private var helpButton: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.quaternary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "About the Actions list"))
        .accessibilityLabel(String(localized: "About the Actions list"))
        .padding(16)
        .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text("Drag to reorder the popup bar or group actions. Turn off an action to hide it. An alias or hotkey triggers an action anywhere.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, alignment: .leading)
            .padding(16)
        }
    }
}

// MARK: - Rows

/// One action in the Actions list: icon, title, enable toggle, and the chevron that opens its page.
/// Alias, hotkey, and delete live on the action's own settings page.
@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    var body: some View {
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages
        )

        HStack(alignment: .center, spacing: 10) {
            ActionIconView(icon: presentationModel.icon, size: 16)
                .frame(width: 20, height: 20, alignment: .center)
                .foregroundStyle(.secondary)

            Text(presentationModel.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                .lineLimit(1)

            if let gated = action as? GatedExtensionAction, let tooltip = extensionGateDescription(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentationModel.title)"))

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
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20, alignment: .center)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
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
            title: String(localized: "Uninstall?"),
            message: "",
            confirmTitle: String(localized: "Uninstall")
        ) {
            Task {
                do {
                    let actionID = InstalledExtensionInfo.info(for: packageID, in: ActionCoordinator.shared.actions)?.uninstallActionID ?? packageID
                    try await ExtensionManager.shared.uninstallExtension(actionID: actionID)
                    NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
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
