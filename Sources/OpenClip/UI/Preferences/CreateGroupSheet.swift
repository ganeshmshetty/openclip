// CreateGroupSheet.swift
// OpenClip
//
// Renders the modal sheet for creating a new custom action group from selected member action IDs.
import SwiftUI
import Core

@MainActor
public struct CreateGroupSheet: View {
    let memberActionIDs: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var iconName: String = "folder"
    @State private var showingIconPicker = false

    public init(memberActionIDs: [String]) {
        self.memberActionIDs = memberActionIDs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Action Group")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Group Name", text: $title)
                    .textFieldStyle(.roundedBorder)

                Button {
                    showingIconPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        AnyIconView(iconId: iconName.isEmpty ? "folder" : iconName)
                            .frame(width: 16, height: 16)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    IconPickerPopover(selectedIcon: $iconName)
                }
            }

            if memberActionIDs.isEmpty {
                Text("Empty group. Drag actions into this group in the actions list.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if memberActionIDs.count == 1 {
                Text("1 action will be grouped.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(String(localized: "\(memberActionIDs.count) actions will be grouped."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    ActionCoordinator.shared.createGroup(
                        title: title.trimmingCharacters(in: .whitespaces),
                        iconName: iconName,
                        memberActionIDs: memberActionIDs
                    )
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
