// CustomizePage.swift
// OpenClip
//
// The Customize page: the popup bar's layout and action enablement, as one reorderable outline.
// Drag to reorder, drag onto a group to add to it, or select rows and group them. Each row has an
// enable toggle and a chevron to its own page. The search field lives in the window toolbar.

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

    /// Top-level standalone actions among `selectedRowIDs` that can join a new group.
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
                // No background, so the empty state reads as part of the pane.
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }


}

// MARK: - Rows

/// One action row: icon, title, enable toggle, and a chevron to its page (alias, hotkey and delete live there).
@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    var coordinator: ActionCoordinator = .shared

    var isRenaming: Bool = false
    var onRename: ((String?) -> Void)? = nil
    @State private var editedTitle = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            coordinator: coordinator
        )
        let parentIsDisabled = coordinator.isDisabledByParentGroup(
            action, disabledActionIDs: disabledActionIDs, disabledPackages: disabledPackages
        )

        HStack(alignment: .center, spacing: 10) {
            ActionIconView(icon: presentationModel.icon, size: 16)
                .frame(width: 20, height: 20, alignment: .center)
                .foregroundStyle(.secondary)
                .opacity(parentIsDisabled ? 0.45 : 1)

            if isRenaming {
                TextField("Action Name", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
                    .frame(maxWidth: 280, alignment: .leading)
                    .focused($nameFocused)
                    .onAppear {
                        editedTitle = presentationModel.title
                        nameFocused = true
                    }
                    .onSubmit { onRename?(editedTitle) }
                    .onExitCommand { onRename?(nil) }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { onRename?(editedTitle) }
                    }
            } else {
                Text(presentationModel.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                    .lineLimit(1)
            }

            if let gated = action as? GatedExtensionAction, let tooltip = extensionGateDescription(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentationModel.title)"))
                .disabled(parentIsDisabled)

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
    @Binding var disabledActionIDs: Set<String>

    var body: some View {
        let isEnabled = ActionEnablement.packageBinding(
            packageID: packageID,
            gatedReason: gatedReason,
            disabledPackages: $disabledPackages,
            disabledActionIDs: $disabledActionIDs
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
