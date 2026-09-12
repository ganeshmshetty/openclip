// NewGroupPage.swift
// OpenClip
//
// Creating a custom action group as a page of the Settings window, seeded with whatever actions
// were selected in the Actions list when it was opened.
import SwiftUI
import Core

@MainActor
public struct NewGroupPage: View {
    let memberActionIDs: [String]
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @State private var title: String = ""
    @State private var iconName: String = "folder"

    public init(memberActionIDs: [String]) {
        self.memberActionIDs = memberActionIDs
    }

    private var members: [any Action] {
        memberActionIDs.compactMap { id in coordinator.actions.first(where: { $0.id == id }) }
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
                            Text("Shown in the popup bar; its actions open in a second row.")
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
                        if members.isEmpty {
                            Text("Empty group. Drag actions into this group in the actions list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(members.enumerated()), id: \.element.id) { index, action in
                                    if index > 0 {
                                        Divider().padding(.horizontal, 12)
                                    }
                                    let presentation = customizationManager.presented(action, surface: .table)
                                    HStack(spacing: 10) {
                                        ActionIconView(icon: presentation.icon, size: 14)
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(.secondary)
                                        Text(presentation.title)
                                            .font(.system(size: 13))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                }
                            }
                        }
                    }

                    Text(memberCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { router.pop() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    ActionCoordinator.shared.createGroup(
                        title: title.trimmingCharacters(in: .whitespaces),
                        iconName: iconName,
                        memberActionIDs: memberActionIDs
                    )
                    router.pop()
                }
                .buttonStyle(.borderedProminent)
                // A group with nothing in it is a row in the popup bar that opens onto nothing,
                // and it would be dropped the moment anything else touched the groups.
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || memberActionIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var memberCountText: String {
        switch memberActionIDs.count {
        case 0: return String(localized: "Select the actions on Customize first, or drag one action onto another to group them.")
        case 1: return String(localized: "1 action will be grouped.")
        default: return String(localized: "\(memberActionIDs.count) actions will be grouped.")
        }
    }
}
