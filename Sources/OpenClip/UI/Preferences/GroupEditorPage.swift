// GroupEditorPage.swift
// OpenClip
//
// A group's settings as a page: its name and icon in the popup bar, its members and their order,
// and — for a group the user made — the way to disband it. Serves both custom groups and the group
// an extension ships, which can be renamed and re-ordered but not disbanded.
import SwiftUI
import Core

@MainActor
public struct GroupEditorPage: View {
    let groupID: String
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared

    @State private var title: String = ""
    @State private var iconName: String = "folder"
    @State private var memberIDs: [String] = []
    @State private var memberIconOverrides: [String: String] = [:]
    @State private var isConfirmingUngroup = false
    @State private var loaded = false

    public init(groupID: String) {
        self.groupID = groupID
    }

    private var groupDef: ActionGroupDef? {
        coordinator.actionGroupDefs.first(where: { $0.id == groupID })
    }

    private var isCustomGroup: Bool {
        groupDef != nil
    }

    private var saveDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
            || (isCustomGroup ? memberIDs.count < 2 : memberIDs.isEmpty)
    }

    public var body: some View {
        SettingsEditorPage {
            VStack(alignment: .leading, spacing: 14) {
                InsetGroupCard {
                    HStack(alignment: .center, spacing: 14) {
                        Button {
                            router.pushIconPicker(writingTo: $iconName)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                    )
                                    .frame(width: 48, height: 48)

                                AnyIconView(iconId: iconName.isEmpty ? "folder" : iconName)
                                    .frame(width: 48, height: 48)

                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.secondary)
                                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1))
                                    .offset(x: 2, y: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Choose icon"))
                        .accessibilityLabel(String(localized: "Choose icon"))

                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Group Name", text: $title)
                                .font(.system(size: 13, weight: .medium))
                                .textFieldStyle(.roundedBorder)
                            Text(isCustomGroup
                                 ? "Shown in the popup bar; its actions open in a second row."
                                 : "The extension's actions open behind this icon in the popup bar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MEMBERS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    InsetGroupCard {
                        VStack(spacing: 0) {
                            ForEach(Array(memberIDs.enumerated()), id: \.element) { index, actionID in
                                if index > 0 {
                                    Divider()
                                        .padding(.horizontal, 12)
                                }
                                GroupMemberRowView(
                                    actionID: actionID,
                                    customIconSymbol: Binding(
                                        get: { memberIconOverrides[actionID] ?? "" },
                                        set: { memberIconOverrides[actionID] = $0 }
                                    ),
                                    isCustomGroup: isCustomGroup,
                                    canMoveUp: index > 0,
                                    canMoveDown: index < memberIDs.count - 1,
                                    onMoveUp: {
                                        guard let idx = memberIDs.firstIndex(of: actionID), idx > 0 else { return }
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            memberIDs.swapAt(idx, idx - 1)
                                        }
                                    },
                                    onMoveDown: {
                                        guard let idx = memberIDs.firstIndex(of: actionID), idx < memberIDs.count - 1 else { return }
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            memberIDs.swapAt(idx, idx + 1)
                                        }
                                    },
                                    onRemove: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            memberIDs.removeAll { $0 == actionID }
                                            memberIconOverrides.removeValue(forKey: actionID)
                                        }
                                    }
                                )
                            }

                            if memberIDs.isEmpty {
                                Text("No actions in this group.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                    }

                    if isCustomGroup {
                        Text("Drag actions onto the group in the Actions list to add more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }
        } footer: {
            HStack(spacing: 12) {
                if isCustomGroup {
                    if isConfirmingUngroup {
                        Text("Ungroup? The actions return to the list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Keep") { isConfirmingUngroup = false }
                        Button("Ungroup", role: .destructive) {
                            coordinator.ungroup(groupID: groupID)
                            router.pop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button("Ungroup…", role: .destructive) {
                            isConfirmingUngroup = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }

                Spacer()

                Button("Cancel") { router.pop() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                    router.pop()
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            load()
        }
    }

    private func load() {
        if let groupDef {
            title = groupDef.title
            iconName = groupDef.iconName.isEmpty ? "folder" : groupDef.iconName
            memberIDs = groupDef.memberActionIDs
        } else {
            let override = ActionCustomizationManager.shared.override(for: groupID)
            let groupAction = coordinator.actions.first(where: { $0.id == groupID })
            title = override?.customTitle ?? groupAction?.title ?? ""
            if let customSymbol = override?.customIconSymbol {
                iconName = customSymbol
            } else if let configurable = groupAction as? any ConfigurableAction, !configurable.preferenceIconName.isEmpty {
                iconName = configurable.preferenceIconName
            } else {
                iconName = "folder"
            }
            memberIDs = coordinator.memberActionIDs(for: groupID)
        }
        var initialIcons: [String: String] = [:]
        for id in memberIDs {
            initialIcons[id] = ActionCustomizationManager.shared.override(for: id)?.customIconSymbol ?? ""
        }
        memberIconOverrides = initialIcons
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let effectiveIcon = iconName.isEmpty ? "folder" : iconName
        if isCustomGroup {
            coordinator.updateGroup(
                groupID: groupID,
                title: trimmedTitle,
                iconName: effectiveIcon,
                memberActionIDs: memberIDs
            )
        } else {
            ActionCustomizationManager.shared.setOverride(
                for: groupID,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                symbol: effectiveIcon,
                text: nil
            )
            coordinator.setExtensionGroupMemberOrder(
                groupID: groupID,
                memberIDs: memberIDs
            )
        }
        for (id, symbol) in memberIconOverrides {
            let existing = ActionCustomizationManager.shared.override(for: id)
            let existingSymbol = existing?.customIconSymbol ?? ""
            if existingSymbol != symbol {
                ActionCustomizationManager.shared.setOverride(
                    for: id,
                    title: existing?.customTitle,
                    symbol: symbol.isEmpty ? nil : symbol,
                    text: existing?.customIconText
                )
            }
        }
    }
}

@MainActor
private struct GroupMemberRowView: View {
    let actionID: String
    @Binding var customIconSymbol: String
    let isCustomGroup: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    private var resolvedAction: (any Action)? {
        coordinator.actions.first(where: { $0.id == actionID })
    }

    private var presentation: ActionPresentationModel? {
        guard let resolvedAction else { return nil }
        let base = customizationManager.presented(resolvedAction, surface: .table)
        if !customIconSymbol.isEmpty {
            return ActionPresentationModel(
                title: base.title,
                icon: .symbol(customIconSymbol)
            )
        } else if customizationManager.override(for: actionID)?.customIconSymbol != nil {
            return ActionPresentationModel(
                title: base.title,
                icon: resolvedAction.icon
            )
        }
        return base
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                router.pushIconPicker(writingTo: $customIconSymbol)
            } label: {
                ZStack {
                    if let presentation {
                        ActionIconView(icon: presentation.icon, size: 14)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 24, height: 24, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Customize Icon"))
            .accessibilityLabel(String(localized: "Customize Icon"))

            Text(presentation?.title ?? actionID)
                .font(.system(size: 13))

            Spacer()

            if canMoveUp || canMoveDown {
                HStack(spacing: 2) {
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    .help(String(localized: "Move Up"))
                    .accessibilityLabel(String(localized: "Move Up"))

                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    .help(String(localized: "Move Down"))
                    .accessibilityLabel(String(localized: "Move Down"))
                }
            }

            if isCustomGroup {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Remove from Group"))
                .accessibilityLabel(String(localized: "Remove from Group"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
