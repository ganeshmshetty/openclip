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

    @State private var editingGroupID: String? = nil
    @State private var selectedRowIDs: Set<String> = []

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

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
        ActionsOutlineView(
            coordinator: coordinator,
            customizationManager: customizationManager,
            selectedRowIDs: $selectedRowIDs,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            onEditGroup: { groupID in
                editingGroupID = groupID
            },
            onCreateGroupFromSelection: {
                showingCreateGroupSheet = true
            }
        )
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
        .sheet(isPresented: $showingCreateGroupSheet, onDismiss: {
            selectedRowIDs = []
        }) {
            CreateGroupSheet(memberActionIDs: candidateSelectedActionIDs)
        }
        .sheet(isPresented: Binding(
            get: { editingGroupID != nil },
            set: { if !$0 { editingGroupID = nil } }
        )) {
            if let editingGroupID {
                EditGroupSheet(groupID: editingGroupID)
            }
        }
    }
}

// MARK: - Action Row View

@MainActor
struct ActionRowView: View {
    let action: any Action
    let presentationModel: ActionPresentationModel
    let isEnabled: Binding<Bool>
    let showsControls: Bool

    init(
        action: any Action,
        presentationModel: ActionPresentationModel,
        isEnabled: Binding<Bool>,
        showsControls: Bool = true
    ) {
        self.action = action
        self.presentationModel = presentationModel
        self.isEnabled = isEnabled
        self.showsControls = showsControls
    }

    private var isAI: Bool {
        ActionIdentity.isAIPreset(action)
    }

    private var isAITools: Bool {
        action.chrome.launchesAI
    }

    @State private var showingConfigSheet = false
    @State private var isHovered = false

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
                                ActionCoordinator.shared.ungroup(groupID: action.id)
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
                Button(action: {
                    showingConfigSheet.toggle()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(showingConfigSheet ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .help(isAITools ? String(localized: "Open AI settings") : (action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action")))
                .accessibilityLabel(isAITools ? String(localized: "Open AI settings") : (action.chrome.rowStyle == .actionGroup ? String(localized: "Configure Group") : String(localized: "Configure Action")))
                .popover(isPresented: $showingConfigSheet, arrowEdge: .leading) {
                    if isAITools {
                        ConfigureAISheet()
                    } else if action.chrome.rowStyle == .actionGroup {
                        EditGroupSheet(groupID: action.id)
                    } else {
                        EditActionSheet(action: action)
                    }
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

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(String(localized: "Enable \(title)"))

            Color.clear
                .frame(width: 20, height: 20)
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
