// CustomizePage.swift
// OpenClip
//
// The Customize page: the popup bar's layout, and nothing else. One reorderable outline of
// everything the bar shows — drag to change the order, drag onto a group to add to it, select
// several rows and make a group of them. An action's own settings (its name, icon, shortcut,
// options, whether it is on) live on the action's page, which the sidebar lists; double-clicking a
// row here is only a shortcut to that page.

import SwiftUI
import UniformTypeIdentifiers
import Core

@MainActor
struct CustomizePage: View {
    /// Owned by the window so the toolbar's "New Group" can seed the group with the selection.
    @Binding var selectedRowIDs: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

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

    var body: some View {
        ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
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
        // Runs the list up into the title bar so its rows fade out under the
        // toolbar like the Form-based panes do. `ActionsScrollView` puts the rows
        // themselves back below it.
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerHint
        }
    }

    /// The page's only instructions, since it has no controls to speak for it.
    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .foregroundStyle(.tertiary)
            Text("Drag to reorder the popup bar. Drop one action onto another to group them, or onto a group to add it; drag the last one out and the group goes. Double-click a row to open its settings.")
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

/// One action in the Customize list: icon and name. Rows used to carry a delete button, a
/// settings gear and an enable switch; all three live on the action's page now.
@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ActionIconView(icon: presentationModel.icon, size: 14)
                .frame(width: 20, height: 20, alignment: .center)
                .foregroundStyle(.secondary)

            Text(presentationModel.title)
                .font(.system(size: 13, weight: .medium))

            if let gated = action as? GatedExtensionAction, let tooltip = extensionGateDescription(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer()
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The header row of a multi-action package that is not a group: a label for the rows under it.
@MainActor
struct PackageHeaderRowView: View {
    let title: String
    let gatedReason: ExtensionGateReason?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
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

            Spacer()
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
    }
}

/// Why a package is gated, as a tooltip on a red dot. The extension's page shows the same text
/// inline, so the dot only has to hint.
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
