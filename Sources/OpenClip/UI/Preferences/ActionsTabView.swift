// ActionsTabView.swift
// OpenClip
//
// The Actions preferences tab: the reorderable action outline tree with per-action toggles,
// native folder drop highlighting, spring-loaded expansion, and add/install controls.

import SwiftUI
import UniformTypeIdentifiers
import Core

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    @Binding var showingAddActionSheet: Bool
    @Binding var showingCreateGroupSheet: Bool

    @State private var selectedRowIDs: Set<String> = []

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var navigator = SettingsNavigator.shared

    /// Eligible candidate action IDs for custom grouping. Only top-level standalone actions
    /// (not AI presets, not AI launcher, not group parents, not extension sub-actions,
    /// and not existing custom group members) can be selected for a new group.
    var candidateSelectedActionIDs: [String] {
        let customGroupMemberIDs = Set(coordinator.actionGroupDefs.flatMap(\.memberActionIDs))

        return coordinator.actions.compactMap { action in
            guard selectedRowIDs.contains(action.id) else { return nil }
            guard coordinator.isEligibleForGrouping(actionID: action.id) else { return nil }
            if customGroupMemberIDs.contains(action.id) { return nil }
            return action.id
        }
    }

    var body: some View {
        // One column, a stack of pages. Every sub-setting that used to float over this list is a
        // level of it now.
        SettingsNavigationStack(navigator: navigator) {
            outline
        } page: { page in
            self.page(page)
        }
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
        .sheet(isPresented: $showingCreateGroupSheet, onDismiss: {
            selectedRowIDs = []
        }) {
            CreateGroupSheet(memberActionIDs: candidateSelectedActionIDs)
        }
        // A page outlives neither the pane nor the action it edits.
        .onDisappear {
            navigator.popToRoot()
        }
    }

    /// The root of the stack: the reorderable action outline.
    private var outline: some View {
        ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
            selectedRowIDs: $selectedRowIDs,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            onEditGroup: { groupID in
                navigator.push(.group(id: groupID))
            },
            onCreateGroupFromSelection: {
                showingCreateGroupSheet = true
            }
        )
        // Runs the list up into the title bar so its rows fade out under the
        // toolbar like the Form-based panes do. `ActionsScrollView` puts the rows
        // themselves back below it.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Content for each level of the stack. A page whose subject disappeared while it was open
    /// (uninstalled extension, ungrouped group) pops itself rather than showing an empty page.
    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .action(let id):
            if let action = coordinator.actions.first(where: { $0.id == id }) {
                EditActionSheet(action: action, isPage: true)
            } else {
                missingSubject
            }
        case .group(let id):
            if coordinator.actions.contains(where: { $0.id == id }) {
                EditGroupSheet(groupID: id, isPage: true)
            } else {
                missingSubject
            }
        case .iconPicker:
            if let target = navigator.iconTarget {
                IconPickerPage(selectedIcon: target) { navigator.pop() }
            } else {
                missingSubject
            }
        case .ai:
            AIConfigurePage()
        case .aiActions:
            AIActionsPage()
        case .aiPreset(let id):
            AIPresetPage(presetID: id)
        case .aiNewPreset:
            AINewPresetPage()
        }
    }

    private var missingSubject: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { navigator.pop() }
    }
}

// MARK: - Action Row View

/// The trailing controls an Actions-tab row exposes besides its enable toggle. Rows opt out per
/// control rather than all-or-nothing: an extension sub-action is removed with its package, so it
/// never gets the delete control, but it still needs the settings cog when the command declares
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

    /// Drills into this row's settings.
    private func openSettings() {
        if isAITools {
            SettingsNavigator.shared.push(.ai)
        } else if action.chrome.rowStyle == .actionGroup {
            SettingsNavigator.shared.push(.group(id: action.id))
        } else {
            SettingsNavigator.shared.push(.action(id: action.id))
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon Column: Glyph-First, clean optical centering without background box
            ActionIconView(icon: presentationModel.icon, size: 14)
                .frame(width: 20, height: 20, alignment: .center)
                .foregroundColor(.secondary)

            // Title Column
            Text(presentationModel.title)
                .font(.system(size: 13, weight: .medium))

            if let gated = action as? GatedExtensionAction, let tooltip = gateTooltip(for: gated.reason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer()

            // Right-aligned controls: delete | settings | enableordisable
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
                                    do {
                                        try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                                    } catch {
                                        Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                                        let failure = NSAlert()
                                        failure.messageText = String(localized: "Remove Failed")
                                        failure.informativeText = String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                                        failure.alertStyle = .warning
                                        failure.runModal()
                                    }
                                } else {
                                    ActionCoordinator.shared.ungroup(groupID: action.id)
                                }
                            } else if case .custom = action.chrome.source {
                                ActionCoordinator.shared.deleteCustomAction(actionID: action.id)
                                ActionCustomizationManager.shared.resetOverride(for: action.id)
                            } else {
                                do {
                                    try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                                } catch {
                                    Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                                    let failure = NSAlert()
                                    failure.messageText = String(localized: "Remove Failed")
                                    failure.informativeText = String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                                    failure.alertStyle = .warning
                                    failure.runModal()
                                }
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(action.chrome.rowStyle == .actionGroup ? String(localized: "Delete Group") : String(localized: "Remove Action"))
                    .accessibilityLabel(action.chrome.rowStyle == .actionGroup ? String(localized: "Delete Group") : String(localized: "Remove Action"))
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                }

                // Settings
                if controls.contains(.settings) {
                    Button(action: {
                        openSettings()
                    }) {
                        // A chevron, not a gear: the control navigates, and says so.
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(isAITools ? String(localized: "Open AI settings") : (action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action")))
                    .accessibilityLabel(isAITools ? String(localized: "Open AI settings") : (action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action")))
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
}

// MARK: - Package Header Row View

@MainActor
struct PackageHeaderRowView: View {
    let packageID: String
    let title: String
    let gatedReason: ExtensionGateReason?
    @Binding var disabledPackages: Set<String>

    var isEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { gatedReason == nil && !disabledPackages.contains(packageID) },
            set: { enabled in
                if enabled {
                    disabledPackages.remove(packageID)
                    Task {
                        await ExtensionManager.shared.enablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } else {
                    disabledPackages.insert(packageID)
                    Task {
                        await ExtensionManager.shared.disablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20, alignment: .center)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            if let gatedReason, let tooltip = gateTooltip(for: gatedReason) {
                GateInfoIcon(tooltip: tooltip)
            }

            Spacer()

            // Right-aligned controls: delete | (settings placeholder) | enableordisable
            HStack(alignment: .center, spacing: 8) {
                Button(action: {
                    Task {
                        do {
                            try await ExtensionManager.shared.uninstallExtension(actionID: packageID)
                        } catch {
                            Log.extensions.error("Failed to uninstall extension '\(packageID, privacy: .public)': \(error.localizedDescription)")
                            let failure = NSAlert()
                            failure.messageText = String(localized: "Remove Failed")
                            failure.informativeText = String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                            failure.alertStyle = .warning
                            failure.runModal()
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .help(String(localized: "Remove Package"))
                .accessibilityLabel(String(localized: "Remove Package"))

                Color.clear
                    .frame(width: 20, height: 20)

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

private struct GateInfoIcon: View {
    let tooltip: String
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            Text(tooltip)
                .font(.system(size: 11))
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(width: 250, alignment: .leading)
        }
    }
}

private func gateTooltip(for reason: ExtensionGateReason) -> String? {
    switch reason {
    case .filesChanged:
        return String(localized: "This extension was modified externally. Toggle on to verify and re-enable.")
    case .notEnabled:
        return String(localized: "New extension found in folder. Toggle on to enable.")
    case .needsNewerApp(let required):
        return String(localized: "This extension requires OpenClip \(required) or newer.")
    case .revoked:
        return nil
    }
}
