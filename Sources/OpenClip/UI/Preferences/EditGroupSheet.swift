// EditGroupSheet.swift
// OpenClip
//
// Renders the modal sheet for editing custom action group metadata, managing members, or disbanding the group.
import SwiftUI
import Core

@MainActor
public struct EditGroupSheet: View {
    let groupID: String
    /// `true` when the editor is a page of the Actions pane's navigation stack, which draws the
    /// title and the way back itself.
    let isPage: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared

    @State private var title: String = ""
    @State private var iconName: String = "folder"
    @State private var memberIDs: [String] = []
    @State private var memberIconOverrides: [String: String] = [:]

    public init(groupID: String, isPage: Bool = false) {
        self.groupID = groupID
        self.isPage = isPage
    }

    private var groupDef: ActionGroupDef? {
        coordinator.actionGroupDefs.first(where: { $0.id == groupID })
    }

    private var isCustomGroup: Bool {
        groupDef != nil
    }

    private func close() {
        if isPage {
            navigator.pop()
        } else {
            dismiss()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isPage {
                HStack {
                    Text("Edit Group")
                        .font(.headline)
                    Spacer()
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                TextField("Group Name", text: $title)
                    .textFieldStyle(.roundedBorder)

                Button {
                    navigator.pushIconPicker(
                        title: String(localized: "Choose Icon"),
                        writingTo: $iconName
                    )
                } label: {
                    HStack(spacing: 4) {
                        AnyIconView(iconId: iconName.isEmpty ? "folder" : iconName)
                            .frame(width: 16, height: 16)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Choose icon"))
            }

            Text("MEMBERS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                ForEach(memberIDs, id: \.self) { actionID in
                    let index = memberIDs.firstIndex(of: actionID) ?? 0
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
            }

            Divider()

            HStack {
                if isCustomGroup {
                    Button("Ungroup", role: .destructive) {
                        coordinator.ungroup(groupID: groupID)
                        close()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
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
                    close()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (isCustomGroup ? memberIDs.count < 2 : memberIDs.isEmpty))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: isPage ? nil : 360)
        .frame(maxWidth: isPage ? .infinity : nil, maxHeight: isPage ? .infinity : nil, alignment: .top)
        .onAppear {
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
    @ObservedObject private var navigator = SettingsNavigator.shared

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
        HStack(spacing: 8) {
            Button {
                navigator.pushIconPicker(
                    title: String(localized: "Choose Icon"),
                    writingTo: $customIconSymbol
                )
            } label: {
                ZStack {
                    if let presentation {
                        ActionIconView(icon: presentation.icon, size: 14)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 22, height: 22, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Customize Icon"))
            .accessibilityLabel(String(localized: "Customize Icon"))

            Text(presentation?.title ?? actionID)
                .font(.system(size: 12))

            Spacer()

            if canMoveUp || canMoveDown {
                HStack(spacing: 4) {
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(canMoveUp ? .secondary : .secondary.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveUp)
                    .help(String(localized: "Move Up"))
                    .accessibilityLabel(String(localized: "Move Up"))

                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(canMoveDown ? .secondary : .secondary.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveDown)
                    .help(String(localized: "Move Down"))
                    .accessibilityLabel(String(localized: "Move Down"))
                }
                .padding(.trailing, 4)
            }

            if isCustomGroup {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }
}

