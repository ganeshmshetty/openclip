// ActionSettingsPane.swift
// OpenClip
//
// A single action's settings as a full pane of the Preferences window, reached from the Actions
// list or from the Shortcuts table.
//
// This is what used to be an `.applicationDefined` NSPopover pinned to a list row: a 370pt floating
// panel that ignored clicks in the list behind it, ignored Escape, and stayed up when you changed
// preference tabs. As a pane it gets the window's width, the sidebar says which action it belongs
// to, and leaving it is the same gesture as leaving any other pane.

import SwiftUI
import Core

@MainActor
struct ActionSettingsPane: View {
    let actionID: String

    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared

    private var action: (any Action)? {
        coordinator.actions.first(where: { $0.id == actionID })
    }

    var body: some View {
        Group {
            if let action {
                VStack(spacing: 0) {
                    breadcrumb

                    Divider()

                    ScrollView {
                        editor(for: action)
                            .padding(.vertical, 4)
                    }
                }
                // Seed the editor per action: the editors load their draft in `onAppear`, so
                // reusing one view across two actions would show the first one's draft.
                .id(action.id)
            } else {
                // The action went away while its page was open (uninstalled extension, ungrouped
                // group). Go back to the list rather than show an empty pane.
                Color.clear.onAppear { router.backToActions() }
            }
        }
    }

    /// "‹ Actions" — the page says where it sits, and the way back is one click, matching the
    /// sidebar row that is highlighted underneath Actions.
    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button {
                router.backToActions()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Actions")
                        .font(.system(size: 12))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func editor(for action: any Action) -> some View {
        if action.chrome.rowStyle == .actionGroup {
            EditGroupSheet(groupID: action.id, isPane: true)
        } else {
            EditActionSheet(action: action, isPane: true)
        }
    }
}
