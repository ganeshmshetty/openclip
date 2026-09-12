// ActionsTabView.swift
// OpenClip
//
// The Actions settings page: the reorderable action outline tree with per-action toggles,
// native folder drop highlighting, spring-loaded expansion, and multi-selection. Every row's
// settings are a page the router navigates to — an action's editor, a group's editor, an
// extension's page, or the AI page — never a layer floated over the list.

import SwiftUI
import UniformTypeIdentifiers
import Core

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
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

    /// Where a row's settings live. AI Tools is a provider's worth of configuration, so it has its
    /// own sidebar page; an extension's group row is the extension itself, so it opens the
    /// extension's page; everything else — a builtin, a custom action, a group the user made, one
    /// command of an extension — opens its own editor.
    static func settingsPage(for action: any Action) -> SettingsPage {
        if action.chrome.launchesAI {
            return .ai
        }
        if let gated = action as? GatedExtensionAction {
            return .extensionPackage(id: gated.packageID)
        }
        if action.chrome.popupBehavior == .showSubActions,
           let packageID = ActionIdentity.extensionPackageID(of: action),
           !InstalledExtensionInfo.isCustomPackage(packageID) {
            return .extensionPackage(id: packageID)
        }
        return .action(id: action.id)
    }

    /// Navigates to a page: a sidebar page is selected, anything else is drilled into.
    static func open(_ page: SettingsPage) {
        if page.isSidebarPage {
            SettingsRouter.shared.select(page)
        } else {
            SettingsRouter.shared.push(page)
        }
    }

    var body: some View {
        ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
            selectedRowIDs: $selectedRowIDs,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
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
                    SettingsRouter.shared.select(.extensionPackage(id: packageID))
                default:
                    if let action = node.action {
                        Self.open(Self.settingsPage(for: action))
                    }
                }
            }
        )
        // Runs the list up into the title bar so its rows fade out under the
        // toolbar like the Form-based panes do. `ActionsScrollView` puts the rows
        // themselves back below it.
        .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - Action Row View

/// The trailing controls an Actions-tab row exposes besides its enable toggle. Rows opt out per
/// control rather than all-or-nothing: an extension sub-action is removed with its package, so it
/// never gets the delete control, but it still needs the settings chevron when the command declares
/// options (`OutlineNode.rowControls` makes that call).
struct ActionRowControls: OptionSet, Sendable {
    let rawValue: Int

    static let delete = ActionRowControls(rawValue: 1 << 0)
    static let settings = ActionRowControls(rawValue: 1 << 1)
    static let all: ActionRowControls = [.delete, .settings]
}

@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel
    let isEnabled: Binding<Bool>
    let controls: ActionRowControls

    init(
        action: any Action,
        presentationModel: ActionPresentationModel,
        isEnabled: Binding<Bool>,
        controls: ActionRowControls = .all
    ) {
        self.action = action
        self.presentationModel = presentationModel
        self.isEnabled = isEnabled
        self.controls = controls
    }

    private var isAI: Bool {
        ActionIdentity.isAIPreset(action)
    }

    private var isAITools: Bool {
        action.chrome.launchesAI
    }

    @State private var isHovered = false

    private var settingsPage: SettingsPage {
        ActionsTab.settingsPage(for: action)
    }

    /// What the chevron opens, for the tooltip and accessibility label.
    private var settingsHelp: String {
        switch settingsPage {
        case .ai: return String(localized: "Open AI Settings")
        case .extensionPackage: return String(localized: "Open Extension Settings")
        default:
            return action.chrome.rowStyle == .actionGroup
                ? String(localized: "Configure Group")
                : String(localized: "Configure Action")
        }
    }

    private func openSettings() {
        ActionsTab.open(settingsPage)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon Column: Glyph-First, clean optical centering without background box
            ActionIconView(icon: presentationModel.icon, size: 14)
                .frame(width: 20, height: 20, alignment: .center)
                .foregroundStyle(.secondary)

            // Title Column
            Text(presentationModel.title)
                .font(.system(size: 13, weight: .medium))

            if let gated = action as? GatedExtensionAction, let tooltip = extensionGateDescription(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer()

            // Right-aligned controls: delete | settings | enable
            HStack(alignment: .center, spacing: 8) {
                // Delete: only for custom actions, extension packages, or custom groups (builtins cannot be uninstalled)
                let canDelete: Bool = {
                    if !controls.contains(.delete) { return false }
                    if action.chrome.rowStyle == .actionGroup { return true }
                    switch action.chrome.source {
                    case .custom, .extensionPkg: return true
                    case .builtin, .ai: return false
                    }
                }()

                if canDelete {
                    Button(action: {
                        Task {
                            if action.chrome.rowStyle == .actionGroup {
                                if case .extensionPkg = action.chrome.source {
                                    await Self.uninstall(actionID: action.id)
                                } else {
                                    ActionCoordinator.shared.ungroup(groupID: action.id)
                                }
                            } else if case .custom = action.chrome.source {
                                ActionCoordinator.shared.deleteCustomAction(actionID: action.id)
                                ActionCustomizationManager.shared.resetOverride(for: action.id)
                            } else {
                                await Self.uninstall(actionID: action.id)
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(action.chrome.rowStyle == .actionGroup ? String(localized: "Delete Group") : String(localized: "Remove Action"))
                    .accessibilityLabel(action.chrome.rowStyle == .actionGroup ? String(localized: "Delete Group") : String(localized: "Remove Action"))
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                }

                // Settings: a chevron, not a gear — the control navigates, and says so.
                if controls.contains(.settings) {
                    Button(action: {
                        openSettings()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(settingsHelp)
                    .accessibilityLabel(settingsHelp)
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                }

                // Enable/Disable
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(String(localized: "Enable \(presentationModel.title)"))
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    /// Removes an extension by one of its action ids, reporting a failure inline in the window
    /// rather than in a modal alert.
    static func uninstall(actionID: String) async {
        do {
            try await ExtensionManager.shared.uninstallExtension(actionID: actionID)
        } catch {
            Log.extensions.error("Failed to uninstall extension '\(actionID, privacy: .public)': \(error.localizedDescription)")
            SettingsRouter.shared.notifyError(
                title: String(localized: "Remove Failed"),
                message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
            )
        }
    }
}

// MARK: - Package Header Row View

@MainActor
struct PackageHeaderRowView: View {
    let packageID: String
    let title: String
    let gatedReason: ExtensionGateReason?
    @Binding var disabledPackages: Set<String>

    var isEnabled: Binding<Bool> {
        ActionEnablement.packageBinding(
            packageID: packageID,
            gatedReason: gatedReason,
            disabledPackages: $disabledPackages
        )
    }

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

            // Right-aligned controls: delete | settings | enable
            HStack(alignment: .center, spacing: 8) {
                Button(action: {
                    Task {
                        await ActionRowView.uninstall(actionID: packageID)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .help(String(localized: "Remove Package"))
                .accessibilityLabel(String(localized: "Remove Package"))

                Button(action: {
                    SettingsRouter.shared.select(.extensionPackage(id: packageID))
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .help(String(localized: "Open Extension Settings"))
                .accessibilityLabel(String(localized: "Open Extension Settings"))

                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(String(localized: "Enable \(title)"))
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
    }
}

// MARK: - Gate Info Icon

/// Why a package is gated, as a tooltip on a red dot. It used to open a popover with the same two
/// sentences; the extension's page now shows them inline, so the dot only has to hint.
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
