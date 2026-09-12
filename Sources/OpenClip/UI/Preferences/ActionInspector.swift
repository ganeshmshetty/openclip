// ActionInspector.swift
// OpenClip
//
// The Actions pane as a list plus an inspector: select a row on the left, configure it on the
// right, in the same window, with nothing floating over anything.
//
// The settings used to arrive as a stack of windows — the row gear opened an `.applicationDefined`
// NSPopover, the icon picker opened a popover on top of it, editing an AI prompt opened a sheet
// that dimmed all of it — which meant you could never see the list while changing an action, and
// comparing two actions meant opening and closing the same floating editor twice.
//
// Raycast's Settings does the opposite and it is the reason its extension preferences feel calm:
// an extension is selected in a list, and its commands and options render inline in the detail
// pane, with advanced options as expandable sections rather than new layers. This is that shape.

import SwiftUI
import Core

/// What the inspector is currently showing.
///
/// A shared object rather than tab state because the rows are hosted in an `NSOutlineView` that
/// rebuilds its cell views on every model change, so a row cannot own "am I the inspected one".
@MainActor
final class ActionInspectorModel: ObservableObject {
    static let shared = ActionInspectorModel()

    @Published var inspectedID: String?

    private init() {}

    /// Follows the outline's selection. Multi-selection (used for grouping) leaves the inspector
    /// on its group summary rather than picking an arbitrary member.
    func selectionChanged(to ids: Set<String>) {
        guard ids.count == 1, let only = ids.first else { return }
        inspectedID = only
    }
}

// MARK: - Inspector

@MainActor
struct ActionInspector: View {
    /// Ids selected in the outline, so the inspector can report a multi-selection.
    let selectedRowIDs: Set<String>

    @ObservedObject private var model = ActionInspectorModel.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

    /// Fixed rather than proportional: the inspector holds a form, and a form that reflows with the
    /// window is harder to read than a list that does.
    static let width: CGFloat = 360

    private var inspectedAction: (any Action)? {
        guard let id = model.inspectedID else { return nil }
        return coordinator.actions.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if selectedRowIDs.count > 1 {
                multiSelection
            } else if let action = inspectedAction {
                content(for: action)
                    // Rebuild the editor when the inspected action changes: the editors seed their
                    // drafts in `onAppear`, so reusing one view across two actions would show the
                    // first action's draft under the second one's name.
                    .id(action.id)
            } else {
                empty
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(for action: any Action) -> some View {
        if action.chrome.launchesAI {
            AIInspector()
        } else if action.chrome.rowStyle == .actionGroup {
            EditGroupSheet(groupID: action.id, isInspector: true)
        } else {
            EditActionSheet(action: action, isInspector: true)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Select an action to configure it")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var multiSelection: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("\(selectedRowIDs.count) actions selected")
                .font(.system(size: 13, weight: .medium))
            Text("Use the + button to group them, or select a single action to configure it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - AI

/// AI Tools in the inspector: engine, provider and the prompt library as ordinary sections of one
/// scrolling form, instead of a 440x480 popover with segmented sub-tabs and a modal on top.
@MainActor
struct AIInspector: View {
    var body: some View {
        Form {
            AIConfigureForm(embedded: true)
            AIActionsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
